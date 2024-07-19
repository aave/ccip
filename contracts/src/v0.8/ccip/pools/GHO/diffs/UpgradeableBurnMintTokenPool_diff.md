```diff
diff --git a/src/v0.8/ccip/pools/BurnMintTokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol
index 9af0f22f4c..a46ff915e5 100644
--- a/src/v0.8/ccip/pools/BurnMintTokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol
@@ -1,28 +1,90 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.19;
+pragma solidity ^0.8.0;
 
-import {ITypeAndVersion} from "../../shared/interfaces/ITypeAndVersion.sol";
-import {IBurnMintERC20} from "../../shared/token/ERC20/IBurnMintERC20.sol";
+import {Initializable} from "solidity-utils/contracts/transparent-proxy/Initializable.sol";
 
-import {TokenPool} from "./TokenPool.sol";
-import {BurnMintTokenPoolAbstract} from "./BurnMintTokenPoolAbstract.sol";
+import {ITypeAndVersion} from "../../../shared/interfaces/ITypeAndVersion.sol";
+import {IBurnMintERC20} from "../../../shared/token/ERC20/IBurnMintERC20.sol";
+
+import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";
+import {UpgradeableBurnMintTokenPoolAbstract} from "./UpgradeableBurnMintTokenPoolAbstract.sol";
+import {RateLimiter} from "../../libraries/RateLimiter.sol";
+
+import {IRouter} from "../../interfaces/IRouter.sol";
+
+/// @title UpgradeableBurnMintTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP BurnMintTokenPool
+/// @dev Contract adaptations:
+/// - Implementation of Initializable to allow upgrades
+/// - Move of allowlist and router definition to initialization stage
+contract UpgradeableBurnMintTokenPool is Initializable, UpgradeableBurnMintTokenPoolAbstract, ITypeAndVersion {
+  error Unauthorized(address caller);
 
-/// @notice This pool mints and burns a 3rd-party token.
-/// @dev Pool whitelisting mode is set in the constructor and cannot be modified later.
-/// It either accepts any address as originalSender, or only accepts whitelisted originalSender.
-/// The only way to change whitelisting mode is to deploy a new pool.
-/// If that is expected, please make sure the token's burner/minter roles are adjustable.
-contract BurnMintTokenPool is BurnMintTokenPoolAbstract, ITypeAndVersion {
   string public constant override typeAndVersion = "BurnMintTokenPool 1.4.0";
 
+  /// @notice The address of the rate limiter admin.
+  /// @dev Can be address(0) if none is configured.
+  address internal s_rateLimitAdmin;
+
+  /// @dev Constructor
+  /// @param token The bridgeable token that is managed by this pool.
+  /// @param armProxy The address of the arm proxy
+  /// @param allowlistEnabled True if pool is set to access-controlled mode, false otherwise
   constructor(
-    IBurnMintERC20 token,
-    address[] memory allowlist,
+    address token,
     address armProxy,
-    address router
-  ) TokenPool(token, allowlist, armProxy, router) {}
+    bool allowlistEnabled
+  ) UpgradeableTokenPool(IBurnMintERC20(token), armProxy, allowlistEnabled) {}
 
-  /// @inheritdoc BurnMintTokenPoolAbstract
+  /// @dev Initializer
+  /// @dev The address passed as `owner` must accept ownership after initialization.
+  /// @dev The `allowlist` is only effective if pool is set to access-controlled mode
+  /// @param owner The address of the owner
+  /// @param allowlist A set of addresses allowed to trigger lockOrBurn as original senders
+  /// @param router The address of the router
+  function initialize(address owner, address[] memory allowlist, address router) public virtual initializer {
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
+  }
+
+  /// @notice Sets the rate limiter admin address.
+  /// @dev Only callable by the owner.
+  /// @param rateLimitAdmin The new rate limiter admin address.
+  function setRateLimitAdmin(address rateLimitAdmin) external onlyOwner {
+    s_rateLimitAdmin = rateLimitAdmin;
+  }
+
+  /// @notice Gets the rate limiter admin address.
+  function getRateLimitAdmin() external view returns (address) {
+    return s_rateLimitAdmin;
+  }
+
+  /// @notice Sets the rate limiter admin address.
+  /// @dev Only callable by the owner or the rate limiter admin. NOTE: overwrites the normal
+  /// onlyAdmin check in the base implementation to also allow the rate limiter admin.
+  /// @param remoteChainSelector The remote chain selector for which the rate limits apply.
+  /// @param outboundConfig The new outbound rate limiter config.
+  /// @param inboundConfig The new inbound rate limiter config.
+  function setChainRateLimiterConfig(
+    uint64 remoteChainSelector,
+    RateLimiter.Config memory outboundConfig,
+    RateLimiter.Config memory inboundConfig
+  ) external override {
+    if (msg.sender != s_rateLimitAdmin && msg.sender != owner()) revert Unauthorized(msg.sender);
+
+    _setRateLimitConfig(remoteChainSelector, outboundConfig, inboundConfig);
+  }
+
+  /// @inheritdoc UpgradeableBurnMintTokenPoolAbstract
   function _burn(uint256 amount) internal virtual override {
     IBurnMintERC20(address(i_token)).burn(amount);
   }
```
