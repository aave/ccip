// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Initializable} from "solidity-utils/contracts/transparent-proxy/Initializable.sol";

import {ILiquidityContainer} from "../../../liquiditymanager/interfaces/ILiquidityContainer.sol";
import {ITypeAndVersion} from "../../../shared/interfaces/ITypeAndVersion.sol";

import {Pool} from "../../libraries/Pool.sol";
import {UpgradeableTokenPool} from "./UpgradeableTokenPool.sol";

import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouter} from "../../interfaces/IRouter.sol";

/// @title UpgradeableLockReleaseTokenPool
/// @author Aave Labs
/// @notice Upgradeable version of Chainlink's CCIP LockReleaseTokenPool
/// @dev Contract adaptations:
/// - Implementation of Initializable to allow upgrades
/// - Move of allowlist and router definition to initialization stage
/// - Addition of a bridge limit to regulate the maximum amount of tokens that can be transferred out (burned/locked)
contract UpgradeableLockReleaseTokenPool is UpgradeableTokenPool, ILiquidityContainer, ITypeAndVersion, Initializable {
  using SafeERC20 for IERC20;

  error InsufficientLiquidity();
  error LiquidityNotAccepted();
  error BridgeLimitExceeded(uint256 bridgeLimit);
  error NotEnoughBridgedAmount();

  event BridgeLimitUpdated(uint256 oldBridgeLimit, uint256 newBridgeLimit);
  event BridgeLimitAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

  event LiquidityTransferred(address indexed from, uint256 amount);

  string public constant override typeAndVersion = "LockReleaseTokenPool 1.5.0";

  /// @dev Whether or not the pool accepts liquidity.
  /// External liquidity is not required when there is one canonical token deployed to a chain,
  /// and CCIP is facilitating mint/burn on all the other chains, in which case the invariant
  /// balanceOf(pool) on home chain >= sum(totalSupply(mint/burn "wrapped" token) on all remote chains) should always hold
  bool internal immutable i_acceptLiquidity;
  /// @notice The address of the rebalancer.
  address internal s_rebalancer;

  /// @notice Maximum amount of tokens that can be bridged to other chains
  uint256 private s_bridgeLimit;
  /// @notice Amount of tokens bridged (transferred out)
  /// @dev Must always be equal to or below the bridge limit
  uint256 private s_currentBridged;
  /// @notice The address of the bridge limit admin.
  /// @dev Can be address(0) if none is configured.
  address internal s_bridgeLimitAdmin;

  //   / @dev Constructor
  //   / @param token The bridgeable token that is managed by this pool.
  //   / @param rmnProxy The address of the rmn proxy
  //   / @param allowlistEnabled True if pool is set to access-controlled mode, false otherwise
  //   / @param acceptLiquidity True if the pool accepts liquidity, false otherwise
  constructor(
    IERC20 token,
    address rmnProxy,
    bool allowListEnabled,
    bool acceptLiquidity
  ) UpgradeableTokenPool(token, rmnProxy, allowListEnabled) {
    i_acceptLiquidity = acceptLiquidity;

    _disableInitializers();
  }

  /// @dev Initializer
  /// @dev The address passed as `owner_` must accept ownership after initialization.
  /// @dev The `allowlist` is only effective if pool is set to access-controlled mode
  /// @param owner_ The address of the owner
  /// @param allowlist A set of addresses allowed to trigger lockOrBurn as original senders
  /// @param router The address of the router
  /// @param bridgeLimit The maximum amount of tokens that can be bridged to other chains
  function initialize(
    address owner_,
    address[] memory allowlist,
    address router,
    uint256 bridgeLimit
  ) public initializer {
    if (router == address(0) || owner_ == address(0)) revert ZeroAddressNotAllowed();

    _transferOwnership(owner_);
    s_router = IRouter(router);
    if (i_allowlistEnabled) _applyAllowListUpdates(new address[](0), allowlist);
    s_bridgeLimit = bridgeLimit;
  }

  /// @notice Locks the token in the pool
  /// @dev The _validateLockOrBurn check is an essential security check
  function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) external virtual override returns (Pool.LockOrBurnOutV1 memory) {
    // Increase bridged amount because tokens are leaving the source chain
    if ((s_currentBridged += lockOrBurnIn.amount) > s_bridgeLimit) revert BridgeLimitExceeded(s_bridgeLimit);

    _validateLockOrBurn(lockOrBurnIn);

    emit Locked(msg.sender, lockOrBurnIn.amount);

    return Pool.LockOrBurnOutV1({destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector), destPoolData: ""});
  }

  /// @notice Release tokens from the pool to the recipient
  /// @dev The _validateReleaseOrMint check is an essential security check
  function releaseOrMint(
    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) external virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
    // This should never occur. Amount should never exceed the current bridged amount
    if (releaseOrMintIn.amount > s_currentBridged) revert NotEnoughBridgedAmount();
    // Reduce bridged amount because tokens are back to source chain
    s_currentBridged -= releaseOrMintIn.amount;

    _validateReleaseOrMint(releaseOrMintIn);

    // Release to the recipient
    getToken().safeTransfer(releaseOrMintIn.receiver, releaseOrMintIn.amount);

    emit Released(msg.sender, releaseOrMintIn.receiver, releaseOrMintIn.amount);

    return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
  }

  /// @notice Sets the bridge limit, the maximum amount of tokens that can be bridged out
  /// @dev Only callable by the owner or the bridge limit admin or owner.
  /// @dev Bridge limit changes should be carefully managed, specially when reducing below the current bridged amount
  /// @param newBridgeLimit The new bridge limit
  function setBridgeLimit(uint256 newBridgeLimit) external {
    if (msg.sender != s_bridgeLimitAdmin && msg.sender != owner()) revert Unauthorized(msg.sender);
    uint256 oldBridgeLimit = s_bridgeLimit;
    s_bridgeLimit = newBridgeLimit;
    emit BridgeLimitUpdated(oldBridgeLimit, newBridgeLimit);
  }

  /// @notice Sets the bridge limit admin address.
  /// @dev Only callable by the owner.
  /// @param bridgeLimitAdmin The new bridge limit admin address.
  function setBridgeLimitAdmin(address bridgeLimitAdmin) external onlyOwner {
    address oldAdmin = s_bridgeLimitAdmin;
    s_bridgeLimitAdmin = bridgeLimitAdmin;
    emit BridgeLimitAdminUpdated(oldAdmin, bridgeLimitAdmin);
  }

  /// @notice Gets the bridge limit
  /// @return The maximum amount of tokens that can be transferred out to other chains
  function getBridgeLimit() external view virtual returns (uint256) {
    return s_bridgeLimit;
  }

  /// @notice Gets the current bridged amount to other chains
  /// @return The amount of tokens transferred out to other chains
  function getCurrentBridgedAmount() external view virtual returns (uint256) {
    return s_currentBridged;
  }

  // @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
    return interfaceId == type(ILiquidityContainer).interfaceId || super.supportsInterface(interfaceId);
  }

  /// @notice Gets LiquidityManager, can be address(0) if none is configured.
  /// @return The current liquidity manager.
  function getRebalancer() external view returns (address) {
    return s_rebalancer;
  }

  /// @notice Gets the bridge limiter admin address.
  function getBridgeLimitAdmin() external view returns (address) {
    return s_bridgeLimitAdmin;
  }

  /// @notice Sets the LiquidityManager address.
  /// @dev Only callable by the owner.
  function setRebalancer(address rebalancer) external onlyOwner {
    s_rebalancer = rebalancer;
  }

  /// @notice Checks if the pool can accept liquidity.
  /// @return true if the pool can accept liquidity, false otherwise.
  function canAcceptLiquidity() external view returns (bool) {
    return i_acceptLiquidity;
  }

  /// @notice Adds liquidity to the pool. The tokens should be approved first.
  /// @param amount The amount of liquidity to provide.
  function provideLiquidity(uint256 amount) external {
    if (!i_acceptLiquidity) revert LiquidityNotAccepted();
    if (s_rebalancer != msg.sender) revert Unauthorized(msg.sender);

    i_token.safeTransferFrom(msg.sender, address(this), amount);
    emit LiquidityAdded(msg.sender, amount);
  }

  /// @notice Removed liquidity to the pool. The tokens will be sent to msg.sender.
  /// @param amount The amount of liquidity to remove.
  function withdrawLiquidity(uint256 amount) external {
    if (s_rebalancer != msg.sender) revert Unauthorized(msg.sender);

    if (i_token.balanceOf(address(this)) < amount) revert InsufficientLiquidity();
    i_token.safeTransfer(msg.sender, amount);
    emit LiquidityRemoved(msg.sender, amount);
  }

  /// @notice This function can be used to transfer liquidity from an older version of the pool to this pool. To do so
  /// this pool will have to be set as the rebalancer in the older version of the pool. This allows it to transfer the
  /// funds in the old pool to the new pool.
  /// @dev When upgrading a LockRelease pool, this function can be called at the same time as the pool is changed in the
  /// TokenAdminRegistry. This allows for a smooth transition of both liquidity and transactions to the new pool.
  /// Alternatively, when no multicall is available, a portion of the funds can be transferred to the new pool before
  /// changing which pool CCIP uses, to ensure both pools can operate. Then the pool should be changed in the
  /// TokenAdminRegistry, which will activate the new pool. All new transactions will use the new pool and its
  /// liquidity. Finally, the remaining liquidity can be transferred to the new pool using this function one more time.
  /// @param from The address of the old pool.
  /// @param amount The amount of liquidity to transfer.
  function transferLiquidity(address from, uint256 amount) external onlyOwner {
    UpgradeableLockReleaseTokenPool(from).withdrawLiquidity(amount);

    emit LiquidityTransferred(from, amount);
  }
}
