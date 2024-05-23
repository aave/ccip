```diff
diff --git a/src/v0.8/ccip/pools/TokenPool.sol b/src/v0.8/ccip/pools/UpgradeableTokenPool.sol
index b3571bb449..fcd8948098 100644
--- a/src/v0.8/ccip/pools/TokenPool.sol
+++ b/src/v0.8/ccip/pools/UpgradeableTokenPool.sol
@@ -1,5 +1,5 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.19;
+pragma solidity ^0.8.0;
 
 import {IPool} from "../interfaces/pools/IPool.sol";
 import {IARM} from "../interfaces/IARM.sol";
@@ -15,7 +15,7 @@ import {EnumerableSet} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts
 /// @notice Base abstract class with common functions for all token pools.
 /// A token pool serves as isolated place for holding tokens and token specific logic
 /// that may execute as tokens move across the bridge.
-abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
+abstract contract UpgradeableTokenPool is IPool, OwnerIsCreator, IERC165 {
   using EnumerableSet for EnumerableSet.AddressSet;
   using EnumerableSet for EnumerableSet.UintSet;
   using RateLimiter for RateLimiter.TokenBucket;
@@ -74,23 +74,17 @@ abstract contract TokenPool is IPool, OwnerIsCreator, IERC165 {
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
```
