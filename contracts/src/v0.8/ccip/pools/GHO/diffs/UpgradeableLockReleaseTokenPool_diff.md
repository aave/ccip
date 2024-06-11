```diff
diff --git a/src/v0.8/ccip/pools/LockReleaseTokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableLockReleaseTokenPool.sol
index 1a17fa0398..9a30b1e977 100644
--- a/src/v0.8/ccip/pools/LockReleaseTokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableLockReleaseTokenPool.sol
@@ -1,26 +1,39 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.19;
+pragma solidity ^0.8.0;
 
-import {ITypeAndVersion} from "../../shared/interfaces/ITypeAndVersion.sol";
-import {ILiquidityContainer} from "../../rebalancer/interfaces/ILiquidityContainer.sol";
+import {Initializable} from "solidity-utils/contracts/transparent-proxy/Initializable.sol";
 
-import {TokenPool} from "./TokenPool.sol";
-import {RateLimiter} from "../libraries/RateLimiter.sol";
+import {ITypeAndVersion} from "../../../shared/interfaces/ITypeAndVersion.sol";
+import {ILiquidityContainer} from "../../../rebalancer/interfaces/ILiquidityContainer.sol";
 
-import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
-import {SafeERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";
+import {RateLimiter} from "../../libraries/RateLimiter.sol";
 
-/// @notice Token pool used for tokens on their native chain. This uses a lock and release mechanism.
-/// Because of lock/unlock requiring liquidity, this pool contract also has function to add and remove
-/// liquidity. This allows for proper bookkeeping for both user and liquidity provider balances.
-/// @dev One token per LockReleaseTokenPool.
-contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion {
+import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
+import {SafeERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
+
+import {IRouter} from "../../interfaces/IRouter.sol";
+
+/// @title UpgradeableLockReleaseTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP LockReleaseTokenPool
+/// @dev Contract adaptations:
+/// - Implementation of Initializable to allow upgrades
+/// - Move of allowlist and router definition to initialization stage
+/// - Addition of a bridge limit to regulate the maximum amount of tokens that can be transferred out (burned/locked)
+contract UpgradeableLockReleaseTokenPool is Initializable, UpgradeableTokenPool, ILiquidityContainer, ITypeAndVersion {
   using SafeERC20 for IERC20;
 
   error InsufficientLiquidity();
   error LiquidityNotAccepted();
   error Unauthorized(address caller);
 
+  error BridgeLimitExceeded(uint256 bridgeLimit);
+  error NotEnoughBridgedAmount();
+
+  event BridgeLimitUpdated(uint256 oldBridgeLimit, uint256 newBridgeLimit);
+  event BridgeLimitAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
+
   string public constant override typeAndVersion = "LockReleaseTokenPool 1.4.0";
 
   /// @dev The unique lock release pool flag to signal through EIP 165.
@@ -37,16 +50,55 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
   /// @dev Can be address(0) if none is configured.
   address internal s_rateLimitAdmin;
 
+  /// @notice Maximum amount of tokens that can be bridged to other chains
+  uint256 private s_bridgeLimit;
+  /// @notice Amount of tokens bridged (transferred out)
+  /// @dev Must always be equal to or below the bridge limit
+  uint256 private s_currentBridged;
+  /// @notice The address of the bridge limit admin.
+  /// @dev Can be address(0) if none is configured.
+  address internal s_bridgeLimitAdmin;
+
+  /// @dev Constructor
+  /// @param token The bridgeable token that is managed by this pool.
+  /// @param armProxy The address of the arm proxy
+  /// @param allowlistEnabled True if pool is set to access-controlled mode, false otherwise
+  /// @param acceptLiquidity True if the pool accepts liquidity, false otherwise
   constructor(
-    IERC20 token,
-    address[] memory allowlist,
+    address token,
     address armProxy,
-    bool acceptLiquidity,
-    address router
-  ) TokenPool(token, allowlist, armProxy, router) {
+    bool allowlistEnabled,
+    bool acceptLiquidity
+  ) UpgradeableTokenPool(IERC20(token), armProxy, allowlistEnabled) {
     i_acceptLiquidity = acceptLiquidity;
   }
 
+  /// @dev Initializer
+  /// @dev The address passed as `owner` must accept ownership after initialization.
+  /// @dev The `allowlist` is only effective if pool is set to access-controlled mode
+  /// @param owner The address of the owner
+  /// @param allowlist A set of addresses allowed to trigger lockOrBurn as original senders
+  /// @param router The address of the router
+  /// @param bridgeLimit The maximum amount of tokens that can be bridged to other chains
+  function initialize(
+    address owner,
+    address[] memory allowlist,
+    address router,
+    uint256 bridgeLimit
+  ) public virtual initializer {
+    if (owner == address(0)) revert ZeroAddressNotAllowed();
+    if (router == address(0)) revert ZeroAddressNotAllowed();
+    _transferOwnership(owner);
+
+    s_router = IRouter(router);
+
+    // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
+    if (i_allowlistEnabled) {
+      _applyAllowListUpdates(new address[](0), allowlist);
+    }
+    s_bridgeLimit = bridgeLimit;
+  }
+
   /// @notice Locks the token in the pool
   /// @param amount Amount to lock
   /// @dev The whenHealthy check is important to ensure that even if a ramp is compromised
@@ -66,6 +118,9 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
     whenHealthy
     returns (bytes memory)
   {
+    // Increase bridged amount because tokens are leaving the source chain
+    if ((s_currentBridged += amount) > s_bridgeLimit) revert BridgeLimitExceeded(s_bridgeLimit);
+
     _consumeOutboundRateLimit(remoteChainSelector, amount);
     emit Locked(msg.sender, amount);
     return "";
@@ -83,6 +138,11 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
     uint64 remoteChainSelector,
     bytes memory
   ) external virtual override onlyOffRamp(remoteChainSelector) whenHealthy {
+    // This should never occur. Amount should never exceed the current bridged amount
+    if (amount > s_currentBridged) revert NotEnoughBridgedAmount();
+    // Reduce bridged amount because tokens are back to source chain
+    s_currentBridged -= amount;
+
     _consumeInboundRateLimit(remoteChainSelector, amount);
     getToken().safeTransfer(receiver, amount);
     emit Released(msg.sender, receiver, amount);
@@ -120,11 +180,48 @@ contract LockReleaseTokenPool is TokenPool, ILiquidityContainer, ITypeAndVersion
     s_rateLimitAdmin = rateLimitAdmin;
   }
 
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
   /// @notice Gets the rate limiter admin address.
   function getRateLimitAdmin() external view returns (address) {
     return s_rateLimitAdmin;
   }
 
+  /// @notice Gets the bridge limiter admin address.
+  function getBridgeLimitAdmin() external view returns (address) {
+    return s_bridgeLimitAdmin;
+  }
+
   /// @notice Checks if the pool can accept liquidity.
   /// @return true if the pool can accept liquidity, false otherwise.
   function canAcceptLiquidity() external view returns (bool) {
```
