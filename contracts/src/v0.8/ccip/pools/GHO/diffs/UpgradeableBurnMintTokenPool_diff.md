```diff
diff --git a/src/v0.8/ccip/pools/BurnMintTokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol
index 30203a4ced..6c1813f51d 100644
--- a/src/v0.8/ccip/pools/BurnMintTokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol
@@ -1,33 +1,75 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.24;
+pragma solidity ^0.8.0;

-import {ITypeAndVersion} from "../../shared/interfaces/ITypeAndVersion.sol";
-import {IBurnMintERC20} from "../../shared/token/ERC20/IBurnMintERC20.sol";
+import {ITypeAndVersion} from "../../../shared/interfaces/ITypeAndVersion.sol";
+import {IBurnMintERC20} from "../../../shared/token/ERC20/IBurnMintERC20.sol";

-import {BurnMintTokenPoolAbstract} from "./BurnMintTokenPoolAbstract.sol";
-import {TokenPool} from "./TokenPool.sol";
+import {UpgradeableBurnMintTokenPoolAbstract} from "./UpgradeableBurnMintTokenPoolAbstract.sol";
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";
+
+import {Initializable} from "solidity-utils/contracts/transparent-proxy/Initializable.sol";
+import {IRouter} from "../../interfaces/IRouter.sol";
+
+/// @title UpgradeableBurnMintTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP BurnMintTokenPool
+/// @dev Contract adaptations:
+/// - Implementation of Initializable to allow upgrades
+/// - Move of allowlist and router definition to initialization stage
+/// - Addition of authorized functions to to directly mint/burn liquidity, thereby increasing/reducing the facilitator's bucket level.
+/// - Modifications from inherited contract (see contract for more details):
+///    - UpgradeableTokenPool:
+///       - Remove i_token decimal check in constructor
+///       - Add storage `__gap` for future upgrades.

-/// @notice This pool mints and burns a 3rd-party token.
 /// @dev Pool whitelisting mode is set in the constructor and cannot be modified later.
 /// It either accepts any address as originalSender, or only accepts whitelisted originalSender.
 /// The only way to change whitelisting mode is to deploy a new pool.
 /// If that is expected, please make sure the token's burner/minter roles are adjustable.
 /// @dev This contract is a variant of BurnMintTokenPool that uses `burn(amount)`.
-contract BurnMintTokenPool is BurnMintTokenPoolAbstract, ITypeAndVersion {
+contract UpgradeableBurnMintTokenPool is Initializable, UpgradeableBurnMintTokenPoolAbstract, ITypeAndVersion {
   string public constant override typeAndVersion = "BurnMintTokenPool 1.5.1";

   constructor(
-    IBurnMintERC20 token,
+    address token,
     uint8 localTokenDecimals,
-    address[] memory allowlist,
     address rmnProxy,
-    address router
-  ) TokenPool(token, localTokenDecimals, allowlist, rmnProxy, router) {}
+    bool allowListEnabled
+  ) UpgradeableTokenPool(IBurnMintERC20(token), localTokenDecimals, rmnProxy, allowListEnabled) {}

-  /// @inheritdoc BurnMintTokenPoolAbstract
-  function _burn(
-    uint256 amount
-  ) internal virtual override {
+  function initialize(address owner_, address[] memory allowlist, address router) external initializer {
+    if (router == address(0) || owner_ == address(0)) revert ZeroAddressNotAllowed();
+
+    _transferOwnership(owner_);
+    s_router = IRouter(router);
+    if (i_allowlistEnabled) _applyAllowListUpdates(new address[](0), allowlist);
+  }
+
+  /// @notice Mint an amount of tokens with no additional logic.
+  /// @dev This GHO-specific functionality is designed for migrating bucket levels between
+  /// facilitators. The new pool is expected to mint amount of tokens, while the old pool
+  /// burns an equivalent amount. This ensures the facilitator can be offboarded, as all
+  /// liquidity minted by it must be fully burned.
+  /// @param to The address to which the minted tokens will be transferred.
+  /// @param to The address to which the minted tokens will be transferred. This needs to
+  /// be the old token pool, or the facilitator being offboarded.
+  /// @param amount The amount of tokens to mint and transfer to old pool.
+  function directMint(address to, uint256 amount) external onlyOwner {
+    IBurnMintERC20(address(i_token)).mint(to, amount);
+  }
+
+  /// @notice Burn an amount of tokens with no additional logic.
+  /// @dev This GHO-specific functionality is designed for migrating bucket levels between
+  /// facilitators. The new pool is expected to mint amount of tokens, while the old pool
+  /// burns an equivalent amount. This ensures the facilitator can be offboarded, as all
+  /// liquidity minted by it must be fully burned
+  /// @param amount The amount of tokens to burn.
+  function directBurn(uint256 amount) external onlyOwner {
+    _burn(amount);
+  }
+
+  /// @inheritdoc UpgradeableBurnMintTokenPoolAbstract
+  function _burn(uint256 amount) internal virtual override {
     IBurnMintERC20(address(i_token)).burn(amount);
   }
 }
```
