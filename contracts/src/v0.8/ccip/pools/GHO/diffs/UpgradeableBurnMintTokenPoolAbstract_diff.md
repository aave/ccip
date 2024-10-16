```diff
diff --git a/src/v0.8/ccip/pools/BurnMintTokenPoolAbstract.sol b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPoolAbstract.sol
index 99908c91d0..0e73ccc1d6 100644
--- a/src/v0.8/ccip/pools/BurnMintTokenPoolAbstract.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPoolAbstract.sol
@@ -1,12 +1,12 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.24;
+pragma solidity ^0.8.0;

-import {IBurnMintERC20} from "../../shared/token/ERC20/IBurnMintERC20.sol";
+import {IBurnMintERC20} from "../../../shared/token/ERC20/IBurnMintERC20.sol";

-import {Pool} from "../libraries/Pool.sol";
-import {TokenPool} from "./TokenPool.sol";
+import {Pool} from "../../libraries/Pool.sol";
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";

-abstract contract BurnMintTokenPoolAbstract is TokenPool {
+abstract contract UpgradeableBurnMintTokenPoolAbstract is UpgradeableTokenPool {
   /// @notice Contains the specific burn call for a pool.
   /// @dev overriding this method allows us to create pools with different burn signatures
   /// without duplicating the underlying logic.
```
