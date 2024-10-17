```diff
diff --git a/src/v0.8/ccip/pools/TokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableTokenPool.sol
index b3571bb449..b0aa10016c 100644
--- a/src/v0.8/ccip/pools/TokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableTokenPool.sol
@@ -1,21 +1,24 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.19;
-
-import {IPool} from "../interfaces/pools/IPool.sol";
-import {IARM} from "../interfaces/IARM.sol";
-import {IRouter} from "../interfaces/IRouter.sol";
-
-import {OwnerIsCreator} from "../../shared/access/OwnerIsCreator.sol";
-import {RateLimiter} from "../libraries/RateLimiter.sol";
-
-import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
-import {IERC165} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/introspection/IERC165.sol";
-import {EnumerableSet} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableSet.sol";
-
-/// @notice Base abstract class with common functions for all token pools.
-/// A token pool serves as isolated place for holding tokens and token specific logic
-/// that may execute as tokens move across the bridge.
-abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
+pragma solidity ^0.8.0;
+
+import {IPool} from "../../interfaces/pools/IPool.sol";
+import {IARM} from "../../interfaces/IARM.sol";
+import {IRouter} from "../../interfaces/IRouter.sol";
+
+import {OwnerIsCreator} from "../../../shared/access/OwnerIsCreator.sol";
+import {RateLimiter} from "../../libraries/RateLimiter.sol";
+
+import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
+import {IERC165} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/introspection/IERC165.sol";
+import {EnumerableSet} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableSet.sol";
+
+/// @title UpgradeableTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP TokenPool
+/// @dev Contract adaptations:
+///   - Setters & Getters for new ProxyPool (to support 1.5 CCIP migration on the existing 1.4 Pool)
+///   - Modify `onlyOnRamp` modifier to accept transactions from ProxyPool
+abstract contract UpgradeableTokenPool is IPool, OwnerIsCreator, IERC165 {
   using EnumerableSet for EnumerableSet.AddressSet;
   using EnumerableSet for EnumerableSet.UintSet;
   using RateLimiter for RateLimiter.TokenBucket;
@@ -28,6 +31,7 @@ abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
   error ChainNotAllowed(uint64 remoteChainSelector);
   error BadARMSignal();
   error ChainAlreadyExists(uint64 chainSelector);
+  error ProxyPoolAlreadySet(uint64 remoteChainSelector);

   event Locked(address indexed sender, uint256 amount);
   event Burned(address indexed sender, uint256 amount);
@@ -55,6 +59,12 @@ abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
     RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
   }

+  /// @dev The storage slot for Proxy Pool address, act as an on ramp "wrapper" post ccip 1.5 migration.
+  /// @dev This was added to continue support for 1.2 onRamp during 1.5 migration, and is stored
+  /// this way to avoid storage collision.
+  // bytes32(uint256(keccak256("ccip.pools.GHO.UpgradeableTokenPool.proxyPool")) - 1)
+  bytes32 internal constant PROXY_POOL_SLOT = 0x75bb68f1b335d4dab6963140ecff58281174ef4362bb85a8593ab9379f24fae2;
+
   /// @dev The bridgeable token that is managed by this pool.
   IERC20 internal immutable i_token;
   /// @dev The address of the arm proxy
@@ -74,23 +84,17 @@ abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
   EnumerableSet.UintSet internal s_remoteChainSelectors;
   /// @dev Outbound rate limits. Corresponds to the inbound rate limit for the pool
   /// on the remote chain.
-  mapping(uint64 remoteChainSelector => RateLimiter.TokenBucket) internal s_outboundRateLimits;
+  mapping(uint64 => RateLimiter.TokenBucket) internal s_outboundRateLimits;
   /// @dev Inbound rate limits. This allows per destination chain
   /// token issuer specified rate limiting (e.g. issuers may trust chains to varying
   /// degrees and prefer different limits)
-  mapping(uint64 remoteChainSelector => RateLimiter.TokenBucket) internal s_inboundRateLimits;
+  mapping(uint64 => RateLimiter.TokenBucket) internal s_inboundRateLimits;

-  constructor(IERC20 token, address[] memory allowlist, address armProxy, address router) {
-    if (address(token) == address(0) || router == address(0)) revert ZeroAddressNotAllowed();
+  constructor(IERC20 token, address armProxy, bool allowlistEnabled) {
+    if (address(token) == address(0)) revert ZeroAddressNotAllowed();
     i_token = token;
     i_armProxy = armProxy;
-    s_router = IRouter(router);
-
-    // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
-    i_allowlistEnabled = allowlist.length > 0;
-    if (i_allowlistEnabled) {
-      _applyAllowListUpdates(new address[](0), allowlist);
-    }
+    i_allowlistEnabled = allowlistEnabled;
   }

   /// @notice Get ARM proxy address
@@ -256,7 +260,8 @@ abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
   /// is a permissioned onRamp for the given chain on the Router.
   modifier onlyOnRamp(uint64 remoteChainSelector) {
     if (!isSupportedChain(remoteChainSelector)) revert ChainNotAllowed(remoteChainSelector);
-    if (!(msg.sender == s_router.getOnRamp(remoteChainSelector))) revert CallerIsNotARampOnRouter(msg.sender);
+    if (!(msg.sender == getProxyPool(remoteChainSelector) || msg.sender == s_router.getOnRamp(remoteChainSelector)))
+      revert CallerIsNotARampOnRouter(msg.sender);
     _;
   }

@@ -323,4 +328,32 @@ abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
     if (IARM(i_armProxy).isCursed()) revert BadARMSignal();
     _;
   }
+
+  /// @notice Getter for proxy pool address.
+  /// @param remoteChainSelector The remote chain selector for which the proxy pool is being retrieved.
+  /// @return proxyPool The proxy pool address for the given remoteChainSelector
+  function getProxyPool(uint64 remoteChainSelector) public view returns (address proxyPool) {
+    assembly ("memory-safe") {
+      mstore(0, PROXY_POOL_SLOT)
+      mstore(32, remoteChainSelector)
+      proxyPool := shr(96, shl(96, sload(keccak256(0, 64))))
+    }
+  }
+
+  /// @notice Setter for proxy pool address, only callable by the DAO.
+  /// @param remoteChainSelector The remote chain selector for which the proxy pool is being set.
+  /// @param proxyPool The address of the proxy pool.
+  function setProxyPool(uint64 remoteChainSelector, address proxyPool) external onlyOwner {
+    _setPoolProxy(remoteChainSelector, proxyPool);
+  }
+
+  function _setPoolProxy(uint64 remoteChainSelector, address proxyPool) internal {
+    if (!isSupportedChain(remoteChainSelector)) revert ChainNotAllowed(remoteChainSelector);
+    if (getProxyPool(remoteChainSelector) != address(0)) revert ProxyPoolAlreadySet(remoteChainSelector);
+    assembly ("memory-safe") {
+      mstore(0, PROXY_POOL_SLOT)
+      mstore(32, remoteChainSelector)
+      sstore(keccak256(0, 64), proxyPool)
+    }
+  }
 }
```
