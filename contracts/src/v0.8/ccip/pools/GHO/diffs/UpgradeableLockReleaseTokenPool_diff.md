```diff
diff --git a/src/v0.8/ccip/pools/LockReleaseTokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableLockReleaseTokenPool.sol
index ecc28a14dd..f8ed82bcc7 100644
--- a/src/v0.8/ccip/pools/LockReleaseTokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableLockReleaseTokenPool.sol
@@ -1,25 +1,46 @@
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
-import {IERC165} from "../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
+import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
+import {SafeERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
+import {IERC165} from "../../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";

-/// @notice Token pool used for tokens on their native chain. This uses a lock and release mechanism.
+import {Pool} from "../../libraries/Pool.sol";
+import {IRouter} from "../../interfaces/IRouter.sol";
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";
+
+/// @title UpgradeableLockReleaseTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP LockReleaseTokenPool
+/// @dev Contract adaptations:
+/// - Implementation of Initializable to allow upgrades
+/// - Move of allowlist and router definition to initialization stage
+/// - Addition of a bridge limit to regulate the maximum amount of tokens that can be transferred out (burned/locked)
+/// - Addition of authorized function to update amount of tokens that are currently bridged
+/// - Modifications from inherited contract (see contract for more details):
+///    - UpgradeableTokenPool
+///       - Remove i_token decimal check in constructor
+///       - Add storage `__gap` for future upgrades.
+
+/// @dev Token pool used for tokens on their native chain. This uses a lock and release mechanism.
 /// Because of lock/unlock requiring liquidity, this pool contract also has function to add and remove
 /// liquidity. This allows for proper bookkeeping for both user and liquidity provider balances.
 /// @dev One token per LockReleaseTokenPool.
-contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion {
+contract UpgradeableLockReleaseTokenPool is Initializable, UpgradeableTokenPool, ILiquidityContainer, ITypeAndVersion {
   using SafeERC20 for IERC20;

   error InsufficientLiquidity();
   error LiquidityNotAccepted();
+  error BridgeLimitExceeded(uint256 bridgeLimit);
+  error NotEnoughBridgedAmount();
+
+  event BridgeLimitUpdated(uint256 oldBridgeLimit, uint256 newBridgeLimit);
+  event BridgeLimitAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

   event LiquidityTransferred(address indexed from, uint256 amount);

@@ -33,30 +54,69 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
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
+  // @notice Constructor
+  // @param token The bridgeable token that is managed by this pool.
+  // @param localTokenDecimals The number of decimals of the token that is managed by this pool.
+  // @param rmnProxy The address of the rmn proxy
+  // @param allowlistEnabled True if pool is set to access-controlled mode, false otherwise
+  // @param acceptLiquidity True if the pool accepts liquidity, false otherwise
   constructor(
-    IERC20 token,
+    address token,
     uint8 localTokenDecimals,
-    address[] memory allowlist,
     address rmnProxy,
-    bool acceptLiquidity,
-    address router
-  ) TokenPool(token, localTokenDecimals, allowlist, rmnProxy, router) {
+    bool allowListEnabled,
+    bool acceptLiquidity
+  ) UpgradeableTokenPool(IERC20(token), localTokenDecimals, rmnProxy, allowListEnabled) {
     i_acceptLiquidity = acceptLiquidity;
   }

+  /// @dev Initializer
+  /// @dev The address passed as `owner` must accept ownership after initialization.
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
+  ) external initializer {
+    if (router == address(0) || owner_ == address(0)) revert ZeroAddressNotAllowed();
+
+    _transferOwnership(owner_);
+    s_router = IRouter(router);
+    if (i_allowlistEnabled) _applyAllowListUpdates(new address[](0), allowlist);
+    s_bridgeLimit = bridgeLimit;
+  }
+
   /// @notice Locks the token in the pool
   /// @dev The _validateLockOrBurn check is an essential security check
   function lockOrBurn(
     Pool.LockOrBurnInV1 calldata lockOrBurnIn
   ) external virtual override returns (Pool.LockOrBurnOutV1 memory) {
+    // Increase bridged amount because tokens are leaving the source chain
+    if ((s_currentBridged += lockOrBurnIn.amount) > s_bridgeLimit) revert BridgeLimitExceeded(s_bridgeLimit);
+
     _validateLockOrBurn(lockOrBurnIn);

     emit Locked(msg.sender, lockOrBurnIn.amount);

-    return Pool.LockOrBurnOutV1({
-      destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
-      destPoolData: _encodeLocalDecimals()
-    });
+    return
+      Pool.LockOrBurnOutV1({
+        destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
+        destPoolData: _encodeLocalDecimals()
+      });
   }

   /// @notice Release tokens from the pool to the recipient
@@ -64,11 +124,18 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   function releaseOrMint(
     Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
   ) external virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
+    // This should never occur. Amount should never exceed the current bridged amount
+    if (releaseOrMintIn.amount > s_currentBridged) revert NotEnoughBridgedAmount();
+    // Reduce bridged amount because tokens are back to source chain
+    s_currentBridged -= releaseOrMintIn.amount;
+
     _validateReleaseOrMint(releaseOrMintIn);

     // Calculate the local amount
-    uint256 localAmount =
-      _calculateLocalAmount(releaseOrMintIn.amount, _parseRemoteDecimals(releaseOrMintIn.sourcePoolData));
+    uint256 localAmount = _calculateLocalAmount(
+      releaseOrMintIn.amount,
+      _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
+    );

     // Release to the recipient
     getToken().safeTransfer(releaseOrMintIn.receiver, localAmount);
@@ -79,9 +146,7 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   }

   /// @inheritdoc IERC165
-  function supportsInterface(
-    bytes4 interfaceId
-  ) public pure virtual override returns (bool) {
+  function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
     return interfaceId == type(ILiquidityContainer).interfaceId || super.supportsInterface(interfaceId);
   }

@@ -93,12 +158,55 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion

   /// @notice Sets the LiquidityManager address.
   /// @dev Only callable by the owner.
-  function setRebalancer(
-    address rebalancer
-  ) external onlyOwner {
+  function setRebalancer(address rebalancer) external onlyOwner {
     s_rebalancer = rebalancer;
   }

+  /// @notice Sets the current bridged amount to other chains
+  /// @dev Only callable by the owner.
+  /// @dev Does not emit event, it is expected to only be called during token pool migrations.
+  /// @param newCurrentBridged The new bridged amount
+  function setCurrentBridgedAmount(uint256 newCurrentBridged) external onlyOwner {
+    s_currentBridged = newCurrentBridged;
+  }
+
+  /// @notice Sets the bridge limit, the maximum amount of tokens that can be bridged out
+  /// @dev Only callable by the owner or the bridge limit admin.
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
+  /// @notice Gets the bridge limiter admin address.
+  function getBridgeLimitAdmin() external view returns (address) {
+    return s_bridgeLimitAdmin;
+  }
+
   /// @notice Checks if the pool can accept liquidity.
   /// @return true if the pool can accept liquidity, false otherwise.
   function canAcceptLiquidity() external view returns (bool) {
@@ -107,9 +215,7 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion

   /// @notice Adds liquidity to the pool. The tokens should be approved first.
   /// @param amount The amount of liquidity to provide.
-  function provideLiquidity(
-    uint256 amount
-  ) external {
+  function provideLiquidity(uint256 amount) external {
     if (!i_acceptLiquidity) revert LiquidityNotAccepted();
     if (s_rebalancer != msg.sender) revert Unauthorized(msg.sender);

@@ -119,9 +225,7 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion

   /// @notice Removed liquidity to the pool. The tokens will be sent to msg.sender.
   /// @param amount The amount of liquidity to remove.
-  function withdrawLiquidity(
-    uint256 amount
-  ) external {
+  function withdrawLiquidity(uint256 amount) external {
     if (s_rebalancer != msg.sender) revert Unauthorized(msg.sender);

     if (i_token.balanceOf(address(this)) < amount) revert InsufficientLiquidity();
@@ -141,7 +245,7 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   /// @param from The address of the old pool.
   /// @param amount The amount of liquidity to transfer.
   function transferLiquidity(address from, uint256 amount) external onlyOwner {
-    LockReleaseTokenPool(from).withdrawLiquidity(amount);
+    UpgradeableLockReleaseTokenPool(from).withdrawLiquidity(amount);

     emit LiquidityTransferred(from, amount);
   }
```
