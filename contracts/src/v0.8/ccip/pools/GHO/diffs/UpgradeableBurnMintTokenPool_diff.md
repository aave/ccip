```diff
diff --git a/src/v0.8/ccip/pools/BurnMintTokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol
index c48c8e51fb..df35f45684 100644
--- a/src/v0.8/ccip/pools/BurnMintTokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol
@@ -1,29 +1,56 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.24;
+pragma solidity ^0.8.0;

-import {ITypeAndVersion} from "../../shared/interfaces/ITypeAndVersion.sol";
-import {IBurnMintERC20} from "../../shared/token/ERC20/IBurnMintERC20.sol";
+import {Initializable} from "solidity-utils/contracts/transparent-proxy/Initializable.sol";
+import {ITypeAndVersion} from "../../../shared/interfaces/ITypeAndVersion.sol";
+import {IBurnMintERC20} from "../../../shared/token/ERC20/IBurnMintERC20.sol";

-import {BurnMintTokenPoolAbstract} from "./BurnMintTokenPoolAbstract.sol";
-import {TokenPool} from "./TokenPool.sol";
+import {UpgradeableBurnMintTokenPoolAbstract} from "./UpgradeableBurnMintTokenPoolAbstract.sol";
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";

-/// @notice This pool mints and burns a 3rd-party token.
-/// @dev Pool whitelisting mode is set in the constructor and cannot be modified later.
-/// It either accepts any address as originalSender, or only accepts whitelisted originalSender.
-/// The only way to change whitelisting mode is to deploy a new pool.
-/// If that is expected, please make sure the token's burner/minter roles are adjustable.
-/// @dev This contract is a variant of BurnMintTokenPool that uses `burn(amount)`.
-contract BurnMintTokenPool is BurnMintTokenPoolAbstract, ITypeAndVersion {
+import {IRouter} from "../../interfaces/IRouter.sol";
+
+/// @title UpgradeableBurnMintTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP BurnMintTokenPool
+/// @dev Contract adaptations:
+/// - Implementation of Initializable to allow upgrades
+/// - Move of allowlist and router definition to initialization stage
+/// - Inclusion of rate limit admin who may configure rate limits in addition to owner
+contract UpgradeableBurnMintTokenPool is UpgradeableBurnMintTokenPoolAbstract, ITypeAndVersion, Initializable {
   string public constant override typeAndVersion = "BurnMintTokenPool 1.5.0";

+  /// @dev Constructor
+  /// @param token The bridgeable token that is managed by this pool.
+  /// @param rmnProxy The address of the arm proxy
+  /// @param allowlistEnabled True if pool is set to access-controlled mode, false otherwise
   constructor(
     IBurnMintERC20 token,
-    address[] memory allowlist,
     address rmnProxy,
-    address router
-  ) TokenPool(token, allowlist, rmnProxy, router) {}
+    bool allowlistEnabled
+  ) UpgradeableTokenPool(token, rmnProxy, allowlistEnabled) {
+    _disableInitializers();
+  }
+
+  /// @dev Initializer
+  /// @dev The address passed as `owner_` must accept ownership after initialization.
+  /// @dev The `allowlist` is only effective if pool is set to access-controlled mode
+  /// @param owner_ The address of the owner
+  /// @param allowlist A set of addresses allowed to trigger lockOrBurn as original senders
+  /// @param router The address of the router
+  function initialize(address owner_, address[] memory allowlist, address router) public virtual initializer {
+    if (owner_ == address(0) || router == address(0)) revert ZeroAddressNotAllowed();
+    _transferOwnership(owner_);
+
+    s_router = IRouter(router);
+
+    // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
+    if (i_allowlistEnabled) {
+      _applyAllowListUpdates(new address[](0), allowlist);
+    }
+  }

-  /// @inheritdoc BurnMintTokenPoolAbstract
+  /// @inheritdoc UpgradeableBurnMintTokenPoolAbstract
   function _burn(uint256 amount) internal virtual override {
     IBurnMintERC20(address(i_token)).burn(amount);
   }
```
