```diff
diff --git a/src/v0.8/ccip/pools/LockReleaseTokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableLockReleaseTokenPool.sol
index 3a4a4aef6d..70adc38030 100644
--- a/src/v0.8/ccip/pools/LockReleaseTokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableLockReleaseTokenPool.sol
@@ -1,24 +1,35 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.24;
+pragma solidity ^0.8.0;

-import {ILiquidityContainer} from "../../liquiditymanager/interfaces/ILiquidityContainer.sol";
-import {ITypeAndVersion} from "../../shared/interfaces/ITypeAndVersion.sol";
+import {Initializable} from "solidity-utils/contracts/transparent-proxy/Initializable.sol";

-import {Pool} from "../libraries/Pool.sol";
-import {TokenPool} from "./TokenPool.sol";
+import {ILiquidityContainer} from "../../../liquiditymanager/interfaces/ILiquidityContainer.sol";
+import {ITypeAndVersion} from "../../../shared/interfaces/ITypeAndVersion.sol";

-import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
-import {SafeERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
+import {Pool} from "../../libraries/Pool.sol";
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";

-/// @notice Token pool used for tokens on their native chain. This uses a lock and release mechanism.
-/// Because of lock/unlock requiring liquidity, this pool contract also has function to add and remove
-/// liquidity. This allows for proper bookkeeping for both user and liquidity provider balances.
-/// @dev One token per LockReleaseTokenPool.
-contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion {
+import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
+import {SafeERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
+import {IRouter} from "../../interfaces/IRouter.sol";
+
+/// @title UpgradeableLockReleaseTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP LockReleaseTokenPool
+/// @dev Contract adaptations:
+/// - Implementation of Initializable to allow upgrades
+/// - Move of allowlist and router definition to initialization stage
+/// - Addition of a bridge limit to regulate the maximum amount of tokens that can be transferred out (burned/locked)
+contract UpgradeableLockReleaseTokenPool is UpgradeableTokenPool, ILiquidityContainer, ITypeAndVersion, Initializable {
   using SafeERC20 for IERC20;

   error InsufficientLiquidity();
   error LiquidityNotAccepted();
+  error BridgeLimitExceeded(uint256 bridgeLimit);
+  error NotEnoughBridgedAmount();
+
+  event BridgeLimitUpdated(uint256 oldBridgeLimit, uint256 newBridgeLimit);
+  event BridgeLimitAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

   event LiquidityTransferred(address indexed from, uint256 amount);

@@ -32,14 +43,50 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   /// @notice The address of the rebalancer.
   address internal s_rebalancer;

+  /// @notice Maximum amount of tokens that can be bridged to other chains
+  uint256 private s_bridgeLimit;
+  /// @notice Amount of tokens bridged (transferred out)
+  /// @dev Must always be equal to or below the bridge limit
+  uint256 private s_currentBridged;
+  /// @notice The address of the bridge limit admin.
+  /// @dev Can be address(0) if none is configured.
+  address internal s_bridgeLimitAdmin;
+
+  //   / @dev Constructor
+  //   / @param token The bridgeable token that is managed by this pool.
+  //   / @param rmnProxy The address of the rmn proxy
+  //   / @param allowlistEnabled True if pool is set to access-controlled mode, false otherwise
+  //   / @param acceptLiquidity True if the pool accepts liquidity, false otherwise
   constructor(
     IERC20 token,
-    address[] memory allowlist,
     address rmnProxy,
-    bool acceptLiquidity,
-    address router
-  ) TokenPool(token, allowlist, rmnProxy, router) {
+    bool allowListEnabled,
+    bool acceptLiquidity
+  ) UpgradeableTokenPool(token, rmnProxy, allowListEnabled) {
     i_acceptLiquidity = acceptLiquidity;
+
+    _disableInitializers();
+  }
+
+  /// @dev Initializer
+  /// @dev The address passed as `owner_` must accept ownership after initialization.
+  /// @dev The `allowlist` is only effective if pool is set to access-controlled mode
+  /// @param owner_ The address of the owner
+  /// @param allowlist A set of addresses allowed to trigger lockOrBurn as original senders
+  /// @param router The address of the router
+  /// @param bridgeLimit The maximum amount of tokens that can be bridged to other chains
+  function initialize(
+    address owner_,
+    address[] memory allowlist,
+    address router,
+    uint256 bridgeLimit
+  ) public initializer {
+    if (router == address(0) || owner_ == address(0)) revert ZeroAddressNotAllowed();
+
+    _transferOwnership(owner_);
+    s_router = IRouter(router);
+    if (i_allowlistEnabled) _applyAllowListUpdates(new address[](0), allowlist);
+    s_bridgeLimit = bridgeLimit;
   }

   /// @notice Locks the token in the pool
@@ -47,6 +94,9 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   function lockOrBurn(
     Pool.LockOrBurnInV1 calldata lockOrBurnIn
   ) external virtual override returns (Pool.LockOrBurnOutV1 memory) {
+    // Increase bridged amount because tokens are leaving the source chain
+    if ((s_currentBridged += lockOrBurnIn.amount) > s_bridgeLimit) revert BridgeLimitExceeded(s_bridgeLimit);
+
     _validateLockOrBurn(lockOrBurnIn);

     emit Locked(msg.sender, lockOrBurnIn.amount);
@@ -59,6 +109,11 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   function releaseOrMint(
     Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
   ) external virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
+    // This should never occur. Amount should never exceed the current bridged amount
+    if (releaseOrMintIn.amount > s_currentBridged) revert NotEnoughBridgedAmount();
+    // Reduce bridged amount because tokens are back to source chain
+    s_currentBridged -= releaseOrMintIn.amount;
+
     _validateReleaseOrMint(releaseOrMintIn);

     // Release to the recipient
@@ -69,6 +124,38 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
     return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
   }

+  /// @notice Sets the bridge limit, the maximum amount of tokens that can be bridged out
+  /// @dev Only callable by the owner or the bridge limit admin or owner.
+  /// @dev Bridge limit changes should be carefully managed, specially when reducing below the current bridged amount
+  /// @param newBridgeLimit The new bridge limit
+  function setBridgeLimit(uint256 newBridgeLimit) external {
+    if (msg.sender != s_bridgeLimitAdmin && msg.sender != owner()) revert Unauthorized(msg.sender);
+    uint256 oldBridgeLimit = s_bridgeLimit;
+    s_bridgeLimit = newBridgeLimit;
+    emit BridgeLimitUpdated(oldBridgeLimit, newBridgeLimit);
+  }
+
+  /// @notice Sets the bridge limit admin address.
+  /// @dev Only callable by the owner.
+  /// @param bridgeLimitAdmin The new bridge limit admin address.
+  function setBridgeLimitAdmin(address bridgeLimitAdmin) external onlyOwner {
+    address oldAdmin = s_bridgeLimitAdmin;
+    s_bridgeLimitAdmin = bridgeLimitAdmin;
+    emit BridgeLimitAdminUpdated(oldAdmin, bridgeLimitAdmin);
+  }
+
+  /// @notice Gets the bridge limit
+  /// @return The maximum amount of tokens that can be transferred out to other chains
+  function getBridgeLimit() external view virtual returns (uint256) {
+    return s_bridgeLimit;
+  }
+
+  /// @notice Gets the current bridged amount to other chains
+  /// @return The amount of tokens transferred out to other chains
+  function getCurrentBridgedAmount() external view virtual returns (uint256) {
+    return s_currentBridged;
+  }
+
   // @inheritdoc IERC165
   function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
     return interfaceId == type(ILiquidityContainer).interfaceId || super.supportsInterface(interfaceId);
@@ -80,6 +167,11 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
     return s_rebalancer;
   }

+  /// @notice Gets the bridge limiter admin address.
+  function getBridgeLimitAdmin() external view returns (address) {
+    return s_bridgeLimitAdmin;
+  }
+
   /// @notice Sets the LiquidityManager address.
   /// @dev Only callable by the owner.
   function setRebalancer(address rebalancer) external onlyOwner {
@@ -124,7 +216,7 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   /// @param from The address of the old pool.
   /// @param amount The amount of liquidity to transfer.
   function transferLiquidity(address from, uint256 amount) external onlyOwner {
-    LockReleaseTokenPool(from).withdrawLiquidity(amount);
+    UpgradeableLockReleaseTokenPool(from).withdrawLiquidity(amount);

     emit LiquidityTransferred(from, amount);
   }
```
