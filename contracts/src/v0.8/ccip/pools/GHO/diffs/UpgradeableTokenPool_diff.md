```diff
diff --git a/src/v0.8/ccip/pools/TokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableTokenPool.sol
index ebd613134a..58331aa41f 100644
--- a/src/v0.8/ccip/pools/TokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableTokenPool.sol
@@ -1,22 +1,22 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.24;
+pragma solidity ^0.8.0;

-import {IPoolV1} from "../interfaces/IPool.sol";
-import {IRMN} from "../interfaces/IRMN.sol";
-import {IRouter} from "../interfaces/IRouter.sol";
+import {IPoolV1} from "../../interfaces/IPool.sol";
+import {IRMN} from "../../interfaces/IRMN.sol";
+import {IRouter} from "../../interfaces/IRouter.sol";

-import {OwnerIsCreator} from "../../shared/access/OwnerIsCreator.sol";
-import {Pool} from "../libraries/Pool.sol";
-import {RateLimiter} from "../libraries/RateLimiter.sol";
+import {OwnerIsCreator} from "../../../shared/access/OwnerIsCreator.sol";
+import {Pool} from "../../libraries/Pool.sol";
+import {RateLimiter} from "../../libraries/RateLimiter.sol";

-import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
-import {IERC165} from "../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
-import {EnumerableSet} from "../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/structs/EnumerableSet.sol";
+import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
+import {IERC165} from "../../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
+import {EnumerableSet} from "../../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/structs/EnumerableSet.sol";

 /// @notice Base abstract class with common functions for all token pools.
 /// A token pool serves as isolated place for holding tokens and token specific logic
 /// that may execute as tokens move across the bridge.
-abstract contract TokenPool is IPoolV1, OwnerIsCreator {
+abstract contract UpgradeableTokenPool is IPoolV1, OwnerIsCreator {
   using EnumerableSet for EnumerableSet.AddressSet;
   using EnumerableSet for EnumerableSet.UintSet;
   using RateLimiter for RateLimiter.TokenBucket;
@@ -92,17 +92,13 @@ abstract contract TokenPool is IPoolV1, OwnerIsCreator {
   /// @dev Can be address(0) if none is configured.
   address internal s_rateLimitAdmin;

-  constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router) {
-    if (address(token) == address(0) || router == address(0) || rmnProxy == address(0)) revert ZeroAddressNotAllowed();
+  constructor(IERC20 token, address rmnProxy, bool allowListEnabled) {
+    if (address(token) == address(0) || rmnProxy == address(0)) revert ZeroAddressNotAllowed();
     i_token = token;
     i_rmnProxy = rmnProxy;
-    s_router = IRouter(router);

     // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
-    i_allowlistEnabled = allowlist.length > 0;
-    if (i_allowlistEnabled) {
-      _applyAllowListUpdates(new address[](0), allowlist);
-    }
+    i_allowlistEnabled = allowListEnabled;
   }

   /// @notice Get RMN proxy address
@@ -140,8 +136,10 @@ abstract contract TokenPool is IPoolV1, OwnerIsCreator {

   /// @notice Signals which version of the pool interface is supported
   function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
-    return interfaceId == Pool.CCIP_POOL_V1 || interfaceId == type(IPoolV1).interfaceId
-      || interfaceId == type(IERC165).interfaceId;
+    return
+      interfaceId == Pool.CCIP_POOL_V1 ||
+      interfaceId == type(IPoolV1).interfaceId ||
+      interfaceId == type(IERC165).interfaceId;
   }

   // ================================================================
@@ -183,8 +181,8 @@ abstract contract TokenPool is IPoolV1, OwnerIsCreator {
     // Validates that the source pool address is configured on this pool.
     bytes memory configuredRemotePool = getRemotePool(releaseOrMintIn.remoteChainSelector);
     if (
-      configuredRemotePool.length == 0
-        || keccak256(releaseOrMintIn.sourcePoolAddress) != keccak256(configuredRemotePool)
+      configuredRemotePool.length == 0 ||
+      keccak256(releaseOrMintIn.sourcePoolAddress) != keccak256(configuredRemotePool)
     ) {
       revert InvalidSourcePoolAddress(releaseOrMintIn.sourcePoolAddress);
     }
```
