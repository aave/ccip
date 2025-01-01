```diff
diff --git a/src/v0.8/ccip/pools/TokenPool.sol b/src/v0.8/ccip/pools/GHO/UpgradeableTokenPool.sol
index cd3096f4ef..d0eca208e3 100644
--- a/src/v0.8/ccip/pools/TokenPool.sol
+++ b/src/v0.8/ccip/pools/GHO/UpgradeableTokenPool.sol
@@ -1,26 +1,29 @@
 // SPDX-License-Identifier: BUSL-1.1
-pragma solidity 0.8.24;
+pragma solidity ^0.8.0;

-import {IPoolV1} from "../interfaces/IPool.sol";
-import {IRMN} from "../interfaces/IRMN.sol";
-import {IRouter} from "../interfaces/IRouter.sol";
+import {IPoolV1} from "../../interfaces/IPool.sol";
+import {IRMN} from "../../interfaces/IRMN.sol";
+import {IRouter} from "../../interfaces/IRouter.sol";

-import {Ownable2StepMsgSender} from "../../shared/access/Ownable2StepMsgSender.sol";
-import {Pool} from "../libraries/Pool.sol";
-import {RateLimiter} from "../libraries/RateLimiter.sol";
+import {Ownable2StepMsgSender} from "../../../shared/access/Ownable2StepMsgSender.sol";
+import {Pool} from "../../libraries/Pool.sol";
+import {RateLimiter} from "../../libraries/RateLimiter.sol";

-import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
-import {IERC20Metadata} from
-  "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/extensions/IERC20Metadata.sol";
-import {IERC165} from "../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
-import {EnumerableSet} from "../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/structs/EnumerableSet.sol";
+import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
+import {IERC165} from "../../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/introspection/IERC165.sol";
+import {EnumerableSet} from "../../../vendor/openzeppelin-solidity/v5.0.2/contracts/utils/structs/EnumerableSet.sol";

+/// @title UpgradeableTokenPool
+/// @author Aave Labs
+/// @notice Upgradeable version of Chainlink's CCIP TokenPool
 /// @dev This pool supports different decimals on different chains but using this feature could impact the total number
 /// of tokens in circulation. Since all of the tokens are locked/burned on the source, and a rounded amount is minted/released on the
 /// destination, the number of tokens minted/released could be less than the number of tokens burned/locked. This is because the source
 /// chain does not know about the destination token decimals. This is not a problem if the decimals are the same on both
 /// chains.
-///
+/// @dev Contract adaptations:
+///  - Remove i_token decimal check in constructor.
+///  - Add storage `__gap` for future upgrades.
 /// Example:
 /// Assume there is a token with 6 decimals on chain A and 3 decimals on chain B.
 /// - 1.234567 tokens are burned on chain A.
@@ -29,7 +32,7 @@ import {EnumerableSet} from "../../vendor/openzeppelin-solidity/v5.0.2/contracts
 /// 0.000567 tokens.
 /// In the case of a burnMint pool on chain A, these funds are burned in the pool on chain A.
 /// In the case of a lockRelease pool on chain A, these funds accumulate in the pool on chain A.
-abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
+abstract contract UpgradeableTokenPool is IPoolV1, Ownable2StepMsgSender {
   using EnumerableSet for EnumerableSet.Bytes32Set;
   using EnumerableSet for EnumerableSet.AddressSet;
   using EnumerableSet for EnumerableSet.UintSet;
@@ -99,52 +102,43 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   address internal immutable i_rmnProxy;
   /// @dev The immutable flag that indicates if the pool is access-controlled.
   bool internal immutable i_allowlistEnabled;
-  /// @dev A set of addresses allowed to trigger lockOrBurn as original senders.
-  /// Only takes effect if i_allowlistEnabled is true.
-  /// This can be used to ensure only token-issuer specified addresses can move tokens.
-  EnumerableSet.AddressSet internal s_allowlist;
-  /// @dev The address of the router
-  IRouter internal s_router;
-  /// @dev A set of allowed chain selectors. We want the allowlist to be enumerable to
-  /// be able to quickly determine (without parsing logs) who can access the pool.
-  /// @dev The chain selectors are in uint256 format because of the EnumerableSet implementation.
-  EnumerableSet.UintSet internal s_remoteChainSelectors;
-  mapping(uint64 remoteChainSelector => RemoteChainConfig) internal s_remoteChainConfigs;
-  /// @notice A mapping of hashed pool addresses to their unhashed form. This is used to be able to find the actually
-  /// configured pools and not just their hashed versions.
-  mapping(bytes32 poolAddressHash => bytes poolAddress) internal s_remotePoolAddresses;
-  /// @notice The address of the rate limiter admin.
-  /// @dev Can be address(0) if none is configured.
-  address internal s_rateLimitAdmin;

-  constructor(IERC20 token, uint8 localTokenDecimals, address[] memory allowlist, address rmnProxy, address router) {
-    if (address(token) == address(0) || router == address(0) || rmnProxy == address(0)) revert ZeroAddressNotAllowed();
+  /// @custom:storage-location erc7201:aave-ccip.storage.UpgradeableTokenPool
+  struct UpgradeableTokenPoolStorage {
+    /// @dev A set of addresses allowed to trigger lockOrBurn as original senders.
+    /// Only takes effect if i_allowlistEnabled is true.
+    /// This can be used to ensure only token-issuer specified addresses can move tokens.
+    EnumerableSet.AddressSet s_allowlist;
+    /// @dev The address of the router
+    IRouter s_router;
+    /// @dev A set of allowed chain selectors. We want the allowlist to be enumerable to
+    /// be able to quickly determine (without parsing logs) who can access the pool.
+    /// @dev The chain selectors are in uint256 format because of the EnumerableSet implementation.
+    EnumerableSet.UintSet s_remoteChainSelectors;
+    mapping(uint64 remoteChainSelector => RemoteChainConfig) s_remoteChainConfigs;
+    /// @notice A mapping of hashed pool addresses to their unhashed form. This is used to be able to find the actually
+    /// configured pools and not just their hashed versions.
+    mapping(bytes32 poolAddressHash => bytes poolAddress) s_remotePoolAddresses;
+    /// @notice The address of the rate limiter admin.
+    /// @dev Can be address(0) if none is configured.
+    address s_rateLimitAdmin;
+  }
+
+  // keccak256(abi.encode(uint256(keccak256("aave-ccip.storage.UpgradeableTokenPool")) - 1)) & ~bytes32(uint256(0xff))
+  bytes32 private constant tokenPoolStorage = 0x1ab3bfa252a45708707caa505d2d48da66a0eaf3681c361d338a45044f67f000;
+
+  constructor(IERC20 token, uint8 localTokenDecimals, address rmnProxy, bool allowListEnabled) {
+    if (address(token) == address(0) || rmnProxy == address(0)) revert ZeroAddressNotAllowed();
     i_token = token;
     i_rmnProxy = rmnProxy;
-
-    try IERC20Metadata(address(token)).decimals() returns (uint8 actualTokenDecimals) {
-      if (localTokenDecimals != actualTokenDecimals) {
-        revert InvalidDecimalArgs(localTokenDecimals, actualTokenDecimals);
-      }
-    } catch {
-      // The decimals function doesn't exist, which is possible since it's optional in the ERC20 spec. We skip the check and
-      // assume the supplied token decimals are correct.
-    }
     i_tokenDecimals = localTokenDecimals;

-    s_router = IRouter(router);
-
     // Pool can be set as permissioned or permissionless at deployment time only to save hot-path gas.
-    i_allowlistEnabled = allowlist.length > 0;
-    if (i_allowlistEnabled) {
-      _applyAllowListUpdates(new address[](0), allowlist);
-    }
+    i_allowlistEnabled = allowListEnabled;
   }

   /// @inheritdoc IPoolV1
-  function isSupportedToken(
-    address token
-  ) public view virtual returns (bool) {
+  function isSupportedToken(address token) public view virtual returns (bool) {
     return token == address(i_token);
   }

@@ -163,27 +157,26 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @notice Gets the pool's Router
   /// @return router The pool's Router
   function getRouter() public view returns (address router) {
-    return address(s_router);
+    return address(_getTokenPoolStorage().s_router);
   }

   /// @notice Sets the pool's Router
   /// @param newRouter The new Router
-  function setRouter(
-    address newRouter
-  ) public onlyOwner {
+  function setRouter(address newRouter) public onlyOwner {
+    UpgradeableTokenPoolStorage storage $ = _getTokenPoolStorage();
     if (newRouter == address(0)) revert ZeroAddressNotAllowed();
-    address oldRouter = address(s_router);
-    s_router = IRouter(newRouter);
+    address oldRouter = address($.s_router);
+    $.s_router = IRouter(newRouter);

     emit RouterUpdated(oldRouter, newRouter);
   }

   /// @notice Signals which version of the pool interface is supported
-  function supportsInterface(
-    bytes4 interfaceId
-  ) public pure virtual override returns (bool) {
-    return interfaceId == Pool.CCIP_POOL_V1 || interfaceId == type(IPoolV1).interfaceId
-      || interfaceId == type(IERC165).interfaceId;
+  function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
+    return
+      interfaceId == Pool.CCIP_POOL_V1 ||
+      interfaceId == type(IPoolV1).interfaceId ||
+      interfaceId == type(IERC165).interfaceId;
   }

   // ================================================================
@@ -199,9 +192,7 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @param lockOrBurnIn The input to validate.
   /// @dev This function should always be called before executing a lock or burn. Not doing so would allow
   /// for various exploits.
-  function _validateLockOrBurn(
-    Pool.LockOrBurnInV1 calldata lockOrBurnIn
-  ) internal {
+  function _validateLockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn) internal {
     if (!isSupportedToken(lockOrBurnIn.localToken)) revert InvalidToken(lockOrBurnIn.localToken);
     if (IRMN(i_rmnProxy).isCursed(bytes16(uint128(lockOrBurnIn.remoteChainSelector)))) revert CursedByRMN();
     _checkAllowList(lockOrBurnIn.originalSender);
@@ -219,9 +210,7 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @param releaseOrMintIn The input to validate.
   /// @dev This function should always be called before executing a release or mint. Not doing so would allow
   /// for various exploits.
-  function _validateReleaseOrMint(
-    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
-  ) internal {
+  function _validateReleaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn) internal {
     if (!isSupportedToken(releaseOrMintIn.localToken)) revert InvalidToken(releaseOrMintIn.localToken);
     if (IRMN(i_rmnProxy).isCursed(bytes16(uint128(releaseOrMintIn.remoteChainSelector)))) revert CursedByRMN();
     _onlyOffRamp(releaseOrMintIn.remoteChainSelector);
@@ -247,9 +236,7 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
     return abi.encode(i_tokenDecimals);
   }

-  function _parseRemoteDecimals(
-    bytes memory sourcePoolData
-  ) internal view virtual returns (uint8) {
+  function _parseRemoteDecimals(bytes memory sourcePoolData) internal view virtual returns (uint8) {
     // Fallback to the local token decimals if the source pool data is empty. This allows for backwards compatibility.
     if (sourcePoolData.length == 0) {
       return i_tokenDecimals;
@@ -304,14 +291,14 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @notice Gets the pool address on the remote chain.
   /// @param remoteChainSelector Remote chain selector.
   /// @dev To support non-evm chains, this value is encoded into bytes
-  function getRemotePools(
-    uint64 remoteChainSelector
-  ) public view returns (bytes[] memory) {
-    bytes32[] memory remotePoolHashes = s_remoteChainConfigs[remoteChainSelector].remotePools.values();
+  function getRemotePools(uint64 remoteChainSelector) public view returns (bytes[] memory) {
+    UpgradeableTokenPoolStorage storage $ = _getTokenPoolStorage();
+
+    bytes32[] memory remotePoolHashes = $.s_remoteChainConfigs[remoteChainSelector].remotePools.values();

     bytes[] memory remotePools = new bytes[](remotePoolHashes.length);
     for (uint256 i = 0; i < remotePoolHashes.length; ++i) {
-      remotePools[i] = s_remotePoolAddresses[remotePoolHashes[i]];
+      remotePools[i] = $.s_remotePoolAddresses[remotePoolHashes[i]];
     }

     return remotePools;
@@ -321,16 +308,17 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @param remoteChainSelector Remote chain selector.
   /// @param remotePoolAddress The address of the remote pool.
   function isRemotePool(uint64 remoteChainSelector, bytes calldata remotePoolAddress) public view returns (bool) {
-    return s_remoteChainConfigs[remoteChainSelector].remotePools.contains(keccak256(remotePoolAddress));
+    return
+      _getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].remotePools.contains(
+        keccak256(remotePoolAddress)
+      );
   }

   /// @notice Gets the token address on the remote chain.
   /// @param remoteChainSelector Remote chain selector.
   /// @dev To support non-evm chains, this value is encoded into bytes
-  function getRemoteToken(
-    uint64 remoteChainSelector
-  ) public view returns (bytes memory) {
-    return s_remoteChainConfigs[remoteChainSelector].remoteTokenAddress;
+  function getRemoteToken(uint64 remoteChainSelector) public view returns (bytes memory) {
+    return _getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].remoteTokenAddress;
   }

   /// @notice Adds a remote pool for a given chain selector. This could be due to a pool being upgraded on the remote
@@ -350,7 +338,9 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   function removeRemotePool(uint64 remoteChainSelector, bytes calldata remotePoolAddress) external onlyOwner {
     if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);

-    if (!s_remoteChainConfigs[remoteChainSelector].remotePools.remove(keccak256(remotePoolAddress))) {
+    if (
+      !_getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].remotePools.remove(keccak256(remotePoolAddress))
+    ) {
       revert InvalidRemotePoolForChain(remoteChainSelector, remotePoolAddress);
     }

@@ -358,16 +348,14 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   }

   /// @inheritdoc IPoolV1
-  function isSupportedChain(
-    uint64 remoteChainSelector
-  ) public view returns (bool) {
-    return s_remoteChainSelectors.contains(remoteChainSelector);
+  function isSupportedChain(uint64 remoteChainSelector) public view returns (bool) {
+    return _getTokenPoolStorage().s_remoteChainSelectors.contains(remoteChainSelector);
   }

   /// @notice Get list of allowed chains
   /// @return list of chains.
   function getSupportedChains() public view returns (uint64[] memory) {
-    uint256[] memory uint256ChainSelectors = s_remoteChainSelectors.values();
+    uint256[] memory uint256ChainSelectors = _getTokenPoolStorage().s_remoteChainSelectors.values();
     uint64[] memory chainSelectors = new uint64[](uint256ChainSelectors.length);
     for (uint256 i = 0; i < uint256ChainSelectors.length; ++i) {
       chainSelectors[i] = uint64(uint256ChainSelectors[i]);
@@ -379,27 +367,27 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @notice Sets the permissions for a list of chains selectors. Actual senders for these chains
   /// need to be allowed on the Router to interact with this pool.
   /// @param remoteChainSelectorsToRemove A list of chain selectors to remove.
-  /// @param chainsToAdd A list of chains and their new permission status & rate limits. Rate limits
-  /// are only used when the chain is being added through `allowed` being true.
+  /// @param chainsToAdd A list of chains and their new permission status & rate limits.
   /// @dev Only callable by the owner
   function applyChainUpdates(
     uint64[] calldata remoteChainSelectorsToRemove,
     ChainUpdate[] calldata chainsToAdd
   ) external virtual onlyOwner {
+    UpgradeableTokenPoolStorage storage $ = _getTokenPoolStorage();
     for (uint256 i = 0; i < remoteChainSelectorsToRemove.length; ++i) {
       uint64 remoteChainSelectorToRemove = remoteChainSelectorsToRemove[i];
       // If the chain doesn't exist, revert
-      if (!s_remoteChainSelectors.remove(remoteChainSelectorToRemove)) {
+      if (!$.s_remoteChainSelectors.remove(remoteChainSelectorToRemove)) {
         revert NonExistentChain(remoteChainSelectorToRemove);
       }

       // Remove all remote pool hashes for the chain
-      bytes32[] memory remotePools = s_remoteChainConfigs[remoteChainSelectorToRemove].remotePools.values();
+      bytes32[] memory remotePools = $.s_remoteChainConfigs[remoteChainSelectorToRemove].remotePools.values();
       for (uint256 j = 0; j < remotePools.length; ++j) {
-        s_remoteChainConfigs[remoteChainSelectorToRemove].remotePools.remove(remotePools[j]);
+        $.s_remoteChainConfigs[remoteChainSelectorToRemove].remotePools.remove(remotePools[j]);
       }

-      delete s_remoteChainConfigs[remoteChainSelectorToRemove];
+      delete $.s_remoteChainConfigs[remoteChainSelectorToRemove];

       emit ChainRemoved(remoteChainSelectorToRemove);
     }
@@ -414,11 +402,11 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
       }

       // If the chain already exists, revert
-      if (!s_remoteChainSelectors.add(newChain.remoteChainSelector)) {
+      if (!$.s_remoteChainSelectors.add(newChain.remoteChainSelector)) {
         revert ChainAlreadyExists(newChain.remoteChainSelector);
       }

-      RemoteChainConfig storage remoteChainConfig = s_remoteChainConfigs[newChain.remoteChainSelector];
+      RemoteChainConfig storage remoteChainConfig = $.s_remoteChainConfigs[newChain.remoteChainSelector];

       remoteChainConfig.outboundRateLimiterConfig = RateLimiter.TokenBucket({
         rate: newChain.outboundRateLimiterConfig.rate,
@@ -453,6 +441,8 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @param remoteChainSelector The remote chain selector for which the remote pool address is being added.
   /// @param remotePoolAddress The address of the new remote pool.
   function _setRemotePool(uint64 remoteChainSelector, bytes memory remotePoolAddress) internal {
+    UpgradeableTokenPoolStorage storage $ = _getTokenPoolStorage();
+
     if (remotePoolAddress.length == 0) {
       revert ZeroAddressNotAllowed();
     }
@@ -460,12 +450,12 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
     bytes32 poolHash = keccak256(remotePoolAddress);

     // Check if the pool already exists.
-    if (!s_remoteChainConfigs[remoteChainSelector].remotePools.add(poolHash)) {
+    if (!$.s_remoteChainConfigs[remoteChainSelector].remotePools.add(poolHash)) {
       revert PoolAlreadyAdded(remoteChainSelector, remotePoolAddress);
     }

     // Add the pool to the mapping to be able to un-hash it later.
-    s_remotePoolAddresses[poolHash] = remotePoolAddress;
+    $.s_remotePoolAddresses[poolHash] = remotePoolAddress;

     emit RemotePoolAdded(remoteChainSelector, remotePoolAddress);
   }
@@ -495,26 +485,30 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @notice Sets the rate limiter admin address.
   /// @dev Only callable by the owner.
   /// @param rateLimitAdmin The new rate limiter admin address.
-  function setRateLimitAdmin(
-    address rateLimitAdmin
-  ) external onlyOwner {
-    s_rateLimitAdmin = rateLimitAdmin;
+  function setRateLimitAdmin(address rateLimitAdmin) external onlyOwner {
+    _getTokenPoolStorage().s_rateLimitAdmin = rateLimitAdmin;
     emit RateLimitAdminSet(rateLimitAdmin);
   }

   /// @notice Gets the rate limiter admin address.
   function getRateLimitAdmin() external view returns (address) {
-    return s_rateLimitAdmin;
+    return _getTokenPoolStorage().s_rateLimitAdmin;
   }

   /// @notice Consumes outbound rate limiting capacity in this pool
   function _consumeOutboundRateLimit(uint64 remoteChainSelector, uint256 amount) internal {
-    s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._consume(amount, address(i_token));
+    _getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._consume(
+      amount,
+      address(i_token)
+    );
   }

   /// @notice Consumes inbound rate limiting capacity in this pool
   function _consumeInboundRateLimit(uint64 remoteChainSelector, uint256 amount) internal {
-    s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._consume(amount, address(i_token));
+    _getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._consume(
+      amount,
+      address(i_token)
+    );
   }

   /// @notice Gets the token bucket with its values for the block it was requested at.
@@ -522,7 +516,11 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   function getCurrentOutboundRateLimiterState(
     uint64 remoteChainSelector
   ) external view returns (RateLimiter.TokenBucket memory) {
-    return s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._currentTokenBucketState();
+    return
+      _getTokenPoolStorage()
+        .s_remoteChainConfigs[remoteChainSelector]
+        .outboundRateLimiterConfig
+        ._currentTokenBucketState();
   }

   /// @notice Gets the token bucket with its values for the block it was requested at.
@@ -530,7 +528,11 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   function getCurrentInboundRateLimiterState(
     uint64 remoteChainSelector
   ) external view returns (RateLimiter.TokenBucket memory) {
-    return s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._currentTokenBucketState();
+    return
+      _getTokenPoolStorage()
+        .s_remoteChainConfigs[remoteChainSelector]
+        .inboundRateLimiterConfig
+        ._currentTokenBucketState();
   }

   /// @notice Sets the chain rate limiter config.
@@ -542,7 +544,7 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
     RateLimiter.Config memory outboundConfig,
     RateLimiter.Config memory inboundConfig
   ) external {
-    if (msg.sender != s_rateLimitAdmin && msg.sender != owner()) revert Unauthorized(msg.sender);
+    if (msg.sender != _getTokenPoolStorage().s_rateLimitAdmin && msg.sender != owner()) revert Unauthorized(msg.sender);

     _setRateLimitConfig(remoteChainSelector, outboundConfig, inboundConfig);
   }
@@ -554,9 +556,13 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   ) internal {
     if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
     RateLimiter._validateTokenBucketConfig(outboundConfig, false);
-    s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._setTokenBucketConfig(outboundConfig);
+    _getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].outboundRateLimiterConfig._setTokenBucketConfig(
+      outboundConfig
+    );
     RateLimiter._validateTokenBucketConfig(inboundConfig, false);
-    s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._setTokenBucketConfig(inboundConfig);
+    _getTokenPoolStorage().s_remoteChainConfigs[remoteChainSelector].inboundRateLimiterConfig._setTokenBucketConfig(
+      inboundConfig
+    );
     emit ChainConfigured(remoteChainSelector, outboundConfig, inboundConfig);
   }

@@ -566,31 +572,27 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {

   /// @notice Checks whether remote chain selector is configured on this contract, and if the msg.sender
   /// is a permissioned onRamp for the given chain on the Router.
-  function _onlyOnRamp(
-    uint64 remoteChainSelector
-  ) internal view {
+  function _onlyOnRamp(uint64 remoteChainSelector) internal view {
     if (!isSupportedChain(remoteChainSelector)) revert ChainNotAllowed(remoteChainSelector);
-    if (!(msg.sender == s_router.getOnRamp(remoteChainSelector))) revert CallerIsNotARampOnRouter(msg.sender);
+    if (!(msg.sender == _getTokenPoolStorage().s_router.getOnRamp(remoteChainSelector)))
+      revert CallerIsNotARampOnRouter(msg.sender);
   }

   /// @notice Checks whether remote chain selector is configured on this contract, and if the msg.sender
   /// is a permissioned offRamp for the given chain on the Router.
-  function _onlyOffRamp(
-    uint64 remoteChainSelector
-  ) internal view {
+  function _onlyOffRamp(uint64 remoteChainSelector) internal view {
     if (!isSupportedChain(remoteChainSelector)) revert ChainNotAllowed(remoteChainSelector);
-    if (!s_router.isOffRamp(remoteChainSelector, msg.sender)) revert CallerIsNotARampOnRouter(msg.sender);
+    if (!_getTokenPoolStorage().s_router.isOffRamp(remoteChainSelector, msg.sender))
+      revert CallerIsNotARampOnRouter(msg.sender);
   }

   // ================================================================
   // │                          Allowlist                           │
   // ================================================================

-  function _checkAllowList(
-    address sender
-  ) internal view {
+  function _checkAllowList(address sender) internal view {
     if (i_allowlistEnabled) {
-      if (!s_allowlist.contains(sender)) {
+      if (!_getTokenPoolStorage().s_allowlist.contains(sender)) {
         revert SenderNotAllowed(sender);
       }
     }
@@ -605,7 +607,7 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @notice Gets the allowed addresses.
   /// @return The allowed addresses.
   function getAllowList() external view returns (address[] memory) {
-    return s_allowlist.values();
+    return _getTokenPoolStorage().s_allowlist.values();
   }

   /// @notice Apply updates to the allow list.
@@ -618,10 +620,10 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
   /// @notice Internal version of applyAllowListUpdates to allow for reuse in the constructor.
   function _applyAllowListUpdates(address[] memory removes, address[] memory adds) internal {
     if (!i_allowlistEnabled) revert AllowListNotEnabled();
-
+    UpgradeableTokenPoolStorage storage $ = _getTokenPoolStorage();
     for (uint256 i = 0; i < removes.length; ++i) {
       address toRemove = removes[i];
-      if (s_allowlist.remove(toRemove)) {
+      if ($.s_allowlist.remove(toRemove)) {
         emit AllowListRemove(toRemove);
       }
     }
@@ -630,9 +632,15 @@ abstract contract TokenPool is IPoolV1, Ownable2StepMsgSender {
       if (toAdd == address(0)) {
         continue;
       }
-      if (s_allowlist.add(toAdd)) {
+      if ($.s_allowlist.add(toAdd)) {
         emit AllowListAdd(toAdd);
       }
     }
   }
+
+  function _getTokenPoolStorage() internal pure returns (UpgradeableTokenPoolStorage storage $) {
+    assembly ("memory-safe") {
+      $.slot := tokenPoolStorage
+    }
+  }
 }
```
