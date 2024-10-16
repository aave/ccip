// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {IBurnMintERC20} from "../../../../shared/token/ERC20/IBurnMintERC20.sol";
import {IPool} from "../../../interfaces/pools/IPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {BaseTest} from "../../BaseTest.t.sol";

abstract contract GhoBaseTest is BaseTest {
  address internal ARM_PROXY = makeAddr("ARM_PROXY");
  address internal ROUTER = makeAddr("ROUTER");
  address internal RAMP = makeAddr("RAMP");
  address internal AAVE_DAO = makeAddr("AAVE_DAO");
  address internal PROXY_ADMIN = makeAddr("PROXY_ADMIN");
  address internal USER = makeAddr("USER");

  uint256 public immutable INITIAL_BRIDGE_LIMIT = 100e6 * 1e18;

  struct UtilsStorage {
    uint256[] chainsList;
    mapping(uint256 => address) pools; // chainId => bridgeTokenPool
    mapping(uint256 => address) tokens; // chainId => ghoToken
    mapping(uint256 => uint256) bucketCapacities; // chainId => bucketCapacities
    mapping(uint256 => uint256) bucketLevels; // chainId => bucketLevels
    mapping(uint256 => uint256) liquidity; // chainId => liquidity
    uint256 remoteLiquidity;
    uint256 bridged;
    bool capacityBelowLevelUpdate;
  }

  function _deployUpgradeableBurnMintTokenPool(
    address ghoToken,
    address arm,
    address router,
    address owner,
    address proxyAdmin
  ) internal returns (address) {
    // Deploy BurnMintTokenPool for GHO token on source chain
    UpgradeableBurnMintTokenPool tokenPoolImpl = new UpgradeableBurnMintTokenPool(ghoToken, arm, false);
    // proxy deploy and init
    address[] memory emptyArray = new address[](0);
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address)",
      owner,
      emptyArray,
      router
    );
    TransparentUpgradeableProxy tokenPoolProxy = new TransparentUpgradeableProxy(
      address(tokenPoolImpl),
      proxyAdmin,
      tokenPoolInitParams
    );
    // Manage ownership
    vm.stopPrank();
    vm.prank(owner);
    UpgradeableBurnMintTokenPool(address(tokenPoolProxy)).acceptOwnership();
    vm.startPrank(OWNER);

    return address(tokenPoolProxy);
  }

  function _deployUpgradeableLockReleaseTokenPool(
    address ghoToken,
    address arm,
    address router,
    address owner,
    uint256 bridgeLimit,
    address proxyAdmin
  ) internal returns (address) {
    UpgradeableLockReleaseTokenPool tokenPoolImpl = new UpgradeableLockReleaseTokenPool(ghoToken, arm, false, true);
    // proxy deploy and init
    address[] memory emptyArray = new address[](0);
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address,uint256)",
      owner,
      emptyArray,
      router,
      bridgeLimit
    );
    TransparentUpgradeableProxy tokenPoolProxy = new TransparentUpgradeableProxy(
      address(tokenPoolImpl),
      proxyAdmin,
      tokenPoolInitParams
    );

    // Manage ownership
    vm.stopPrank();
    vm.prank(owner);
    UpgradeableLockReleaseTokenPool(address(tokenPoolProxy)).acceptOwnership();
    vm.startPrank(OWNER);

    return address(tokenPoolProxy);
  }

  function _inflateFacilitatorLevel(address tokenPool, address ghoToken, uint256 amount) internal {
    vm.stopPrank();
    vm.prank(tokenPool);
    IBurnMintERC20(ghoToken).mint(address(0), amount);
  }

  function _getProxyAdminAddress(address proxy) internal view returns (address) {
    bytes32 ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 adminSlot = vm.load(proxy, ERC1967_ADMIN_SLOT);
    return address(uint160(uint256(adminSlot)));
  }

  function _getProxyImplementationAddress(address proxy) internal view returns (address) {
    bytes32 ERC1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 implSlot = vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT);
    return address(uint160(uint256(implSlot)));
  }

  function _getUpgradeableVersion(address proxy) internal view returns (uint8) {
    // version is 1st slot
    return uint8(uint256(vm.load(proxy, bytes32(uint256(0)))));
  }

  function _enableLane(UtilsStorage storage s, uint256 fromId, uint256 toId) internal {
    // from
    UpgradeableTokenPool.ChainUpdate[] memory chainUpdate = new UpgradeableTokenPool.ChainUpdate[](1);
    RateLimiter.Config memory emptyRateConfig = RateLimiter.Config(false, 0, 0);
    chainUpdate[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: uint64(toId),
      allowed: true,
      outboundRateLimiterConfig: emptyRateConfig,
      inboundRateLimiterConfig: emptyRateConfig
    });

    vm.startPrank(OWNER);
    UpgradeableTokenPool(s.pools[fromId]).applyChainUpdates(chainUpdate);

    // to
    chainUpdate[0].remoteChainSelector = uint64(fromId);
    UpgradeableTokenPool(s.pools[toId]).applyChainUpdates(chainUpdate);
    vm.stopPrank();
  }

  function _addBridge(UtilsStorage storage s, uint256 chainId, uint256 bucketCapacity) internal {
    require(s.tokens[chainId] == address(0), "BRIDGE_ALREADY_EXISTS");

    s.chainsList.push(chainId);

    // GHO Token
    GhoToken ghoToken = new GhoToken(AAVE_DAO);
    s.tokens[chainId] = address(ghoToken);

    // UpgradeableTokenPool
    address bridgeTokenPool = _deployUpgradeableBurnMintTokenPool(
      address(ghoToken),
      ARM_PROXY,
      ROUTER,
      OWNER,
      PROXY_ADMIN
    );
    s.pools[chainId] = bridgeTokenPool;

    // Facilitator
    s.bucketCapacities[chainId] = bucketCapacity;
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    ghoToken.grantRole(ghoToken.FACILITATOR_MANAGER_ROLE(), AAVE_DAO);
    ghoToken.addFacilitator(bridgeTokenPool, "UpgradeableTokenPool", uint128(bucketCapacity));
    vm.stopPrank();
  }

  function _updateBridgeLimit(UtilsStorage storage s, uint256 newBridgeLimit) internal {
    vm.stopPrank();
    vm.startPrank(OWNER);
    UpgradeableLockReleaseTokenPool(s.pools[0]).setBridgeLimit(newBridgeLimit);
    vm.stopPrank();
  }

  function _updateBucketCapacity(UtilsStorage storage s, uint256 chainId, uint256 newBucketCapacity) internal {
    s.bucketCapacities[chainId] = newBucketCapacity;
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    GhoToken(s.tokens[chainId]).grantRole(GhoToken(s.tokens[chainId]).BUCKET_MANAGER_ROLE(), AAVE_DAO);
    GhoToken(s.tokens[chainId]).setFacilitatorBucketCapacity(s.pools[chainId], uint128(newBucketCapacity));
    vm.stopPrank();
  }

  function _getCapacity(UtilsStorage storage s, uint256 chain) internal view returns (uint256) {
    require(!_isEthereumChain(chain), "No bucket on Ethereum");
    (uint256 capacity, ) = GhoToken(s.tokens[chain]).getFacilitatorBucket(s.pools[chain]);
    return capacity;
  }

  function _getLevel(UtilsStorage storage s, uint256 chain) internal view returns (uint256) {
    require(!_isEthereumChain(chain), "No bucket on Ethereum");
    (, uint256 level) = GhoToken(s.tokens[chain]).getFacilitatorBucket(s.pools[chain]);
    return level;
  }

  function _getMaxToBridgeOut(UtilsStorage storage s, uint256 fromChain) internal view returns (uint256) {
    if (_isEthereumChain(fromChain)) {
      UpgradeableLockReleaseTokenPool ethTokenPool = UpgradeableLockReleaseTokenPool(s.pools[0]);
      uint256 bridgeLimit = ethTokenPool.getBridgeLimit();
      uint256 currentBridged = ethTokenPool.getCurrentBridgedAmount();
      return currentBridged > bridgeLimit ? 0 : bridgeLimit - currentBridged;
    } else {
      (, uint256 level) = GhoToken(s.tokens[fromChain]).getFacilitatorBucket(s.pools[fromChain]);
      return level;
    }
  }

  function _getMaxToBridgeIn(UtilsStorage storage s, uint256 toChain) internal view returns (uint256) {
    if (_isEthereumChain(toChain)) {
      UpgradeableLockReleaseTokenPool ethTokenPool = UpgradeableLockReleaseTokenPool(s.pools[0]);
      return ethTokenPool.getCurrentBridgedAmount();
    } else {
      (uint256 capacity, uint256 level) = GhoToken(s.tokens[toChain]).getFacilitatorBucket(s.pools[toChain]);
      return level > capacity ? 0 : capacity - level;
    }
  }

  function _bridgeGho(
    UtilsStorage storage s,
    uint256 fromChain,
    uint256 toChain,
    address user,
    uint256 amount
  ) internal {
    _moveGhoOrigin(s, fromChain, toChain, user, amount);
    _moveGhoDestination(s, fromChain, toChain, user, amount);
  }

  function _moveGhoOrigin(
    UtilsStorage storage s,
    uint256 fromChain,
    uint256 toChain,
    address user,
    uint256 amount
  ) internal {
    // Simulate CCIP pull of funds
    vm.startPrank(user);
    GhoToken(s.tokens[fromChain]).transfer(s.pools[fromChain], amount);

    vm.startPrank(RAMP);
    IPool(s.pools[fromChain]).lockOrBurn(user, bytes(""), amount, uint64(toChain), bytes(""));

    if (_isEthereumChain(fromChain)) {
      // Lock
      s.bridged += amount;
    } else {
      // Burn
      s.bucketLevels[fromChain] -= amount;
      s.liquidity[fromChain] -= amount;
      s.remoteLiquidity -= amount;
    }
  }

  function _moveGhoDestination(
    UtilsStorage storage s,
    uint256 fromChain,
    uint256 toChain,
    address user,
    uint256 amount
  ) internal {
    vm.startPrank(RAMP);
    IPool(s.pools[toChain]).releaseOrMint(bytes(""), user, amount, uint64(fromChain), bytes(""));

    if (_isEthereumChain(toChain)) {
      // Release
      s.bridged -= amount;
    } else {
      // Mint
      s.bucketLevels[toChain] += amount;
      s.liquidity[toChain] += amount;
      s.remoteLiquidity += amount;
    }
  }

  function _isEthereumChain(uint256 chainId) internal pure returns (bool) {
    return chainId == 0;
  }
}
