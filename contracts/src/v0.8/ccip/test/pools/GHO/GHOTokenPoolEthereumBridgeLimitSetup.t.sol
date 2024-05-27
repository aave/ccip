// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";

import {BaseTest} from "../../BaseTest.t.sol";
import {IPool} from "../../../interfaces/pools/IPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";

contract GHOTokenPoolEthereumBridgeLimitSetup is BaseTest {
  address internal ARM_PROXY = makeAddr("ARM_PROXY");
  address internal ROUTER = makeAddr("ROUTER");
  address internal RAMP = makeAddr("RAMP");
  address internal AAVE_DAO = makeAddr("AAVE_DAO");
  address internal PROXY_ADMIN = makeAddr("PROXY_ADMIN");
  address internal USER = makeAddr("USER");

  uint256 public immutable INITIAL_BRIDGE_LIMIT = 100e6 * 1e18;

  uint256[] public chainsList;
  mapping(uint256 => address) public pools; // chainId => bridgeTokenPool
  mapping(uint256 => address) public tokens; // chainId => ghoToken
  mapping(uint256 => uint256) public bucketCapacities; // chainId => bucketCapacities
  mapping(uint256 => uint256) public bucketLevels; // chainId => bucketLevels
  mapping(uint256 => uint256) public liquidity; // chainId => liquidity
  uint256 public remoteLiquidity;
  uint256 public bridged;

  function setUp() public virtual override {
    // Ethereum with id 0
    chainsList.push(0);
    tokens[0] = address(new GhoToken(AAVE_DAO));
    pools[0] = _deployUpgradeableLockReleaseTokenPool(
      tokens[0],
      ARM_PROXY,
      ROUTER,
      OWNER,
      INITIAL_BRIDGE_LIMIT,
      PROXY_ADMIN
    );

    // Mock calls for bridging
    vm.mockCall(ROUTER, abi.encodeWithSelector(bytes4(keccak256("getOnRamp(uint64)"))), abi.encode(RAMP));
    vm.mockCall(ROUTER, abi.encodeWithSelector(bytes4(keccak256("isOffRamp(uint64,address)"))), abi.encode(true));
    vm.mockCall(ARM_PROXY, abi.encodeWithSelector(bytes4(keccak256("isCursed()"))), abi.encode(false));
  }

  function _enableLane(uint256 fromId, uint256 toId) internal {
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
    UpgradeableTokenPool(pools[fromId]).applyChainUpdates(chainUpdate);

    // to
    chainUpdate[0].remoteChainSelector = uint64(fromId);
    UpgradeableTokenPool(pools[toId]).applyChainUpdates(chainUpdate);
    vm.stopPrank();
  }

  function _addBridge(uint256 chainId, uint256 bucketCapacity) internal {
    require(tokens[chainId] == address(0), "BRIDGE_ALREADY_EXISTS");

    chainsList.push(chainId);

    // GHO Token
    GhoToken ghoToken = new GhoToken(AAVE_DAO);
    tokens[chainId] = address(ghoToken);

    // UpgradeableTokenPool
    address bridgeTokenPool = _deployUpgradeableBurnMintTokenPool(
      address(ghoToken),
      ARM_PROXY,
      ROUTER,
      OWNER,
      PROXY_ADMIN
    );
    pools[chainId] = bridgeTokenPool;

    // Facilitator
    bucketCapacities[chainId] = bucketCapacity;
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    ghoToken.grantRole(ghoToken.FACILITATOR_MANAGER_ROLE(), AAVE_DAO);
    ghoToken.addFacilitator(bridgeTokenPool, "UpgradeableTokenPool", uint128(bucketCapacity));
    vm.stopPrank();
  }

  function _updateBridgeLimit(uint256 newBridgeLimit) internal {
    vm.prank(OWNER);
    UpgradeableLockReleaseTokenPool(pools[0]).setBridgeLimit(newBridgeLimit);
  }

  function _updateBucketCapacity(uint256 chainId, uint256 newBucketCapacity) internal {
    bucketCapacities[chainId] = newBucketCapacity;
    vm.startPrank(AAVE_DAO);
    GhoToken(tokens[chainId]).grantRole(GhoToken(tokens[chainId]).BUCKET_MANAGER_ROLE(), AAVE_DAO);
    GhoToken(tokens[chainId]).setFacilitatorBucketCapacity(pools[chainId], uint128(newBucketCapacity));
    vm.stopPrank();
  }

  function _getMaxToBridgeOut(uint256 fromChain) internal view returns (uint256) {
    if (_isEthereumChain(fromChain)) {
      UpgradeableLockReleaseTokenPool ethTokenPool = UpgradeableLockReleaseTokenPool(pools[0]);
      uint256 bridgeLimit = ethTokenPool.getBridgeLimit();
      uint256 currentBridged = ethTokenPool.getCurrentBridgedAmount();
      return currentBridged > bridgeLimit ? 0 : bridgeLimit - currentBridged;
    } else {
      (, uint256 level) = GhoToken(tokens[fromChain]).getFacilitatorBucket(pools[fromChain]);
      return level;
    }
  }

  function _getMaxToBridgeIn(uint256 toChain) internal view returns (uint256) {
    if (_isEthereumChain(toChain)) {
      UpgradeableLockReleaseTokenPool ethTokenPool = UpgradeableLockReleaseTokenPool(pools[0]);
      return ethTokenPool.getCurrentBridgedAmount();
    } else {
      (uint256 capacity, uint256 level) = GhoToken(tokens[toChain]).getFacilitatorBucket(pools[toChain]);
      return level > capacity ? 0 : capacity - level;
    }
  }

  function _getCapacity(uint256 chain) internal view returns (uint256) {
    require(!_isEthereumChain(chain), "No bucket on Ethereum");
    (uint256 capacity, ) = GhoToken(tokens[chain]).getFacilitatorBucket(pools[chain]);
    return capacity;
  }

  function _getLevel(uint256 chain) internal view returns (uint256) {
    require(!_isEthereumChain(chain), "No bucket on Ethereum");
    (, uint256 level) = GhoToken(tokens[chain]).getFacilitatorBucket(pools[chain]);
    return level;
  }

  function _bridgeGho(uint256 fromChain, uint256 toChain, address user, uint256 amount) internal {
    _moveGhoOrigin(fromChain, toChain, user, amount);
    _moveGhoDestination(fromChain, toChain, user, amount);
  }

  function _moveGhoOrigin(uint256 fromChain, uint256 toChain, address user, uint256 amount) internal {
    // Simulate CCIP pull of funds
    vm.prank(user);
    GhoToken(tokens[fromChain]).transfer(pools[fromChain], amount);

    vm.prank(RAMP);
    IPool(pools[fromChain]).lockOrBurn(user, bytes(""), amount, uint64(toChain), bytes(""));

    if (_isEthereumChain(fromChain)) {
      // Lock
      bridged += amount;
    } else {
      // Burn
      bucketLevels[fromChain] -= amount;
      liquidity[fromChain] -= amount;
      remoteLiquidity -= amount;
    }
  }

  function _moveGhoDestination(uint256 fromChain, uint256 toChain, address user, uint256 amount) internal {
    vm.prank(RAMP);
    IPool(pools[toChain]).releaseOrMint(bytes(""), user, amount, uint64(fromChain), bytes(""));

    if (_isEthereumChain(toChain)) {
      // Release
      bridged -= amount;
    } else {
      // Mint
      bucketLevels[toChain] += amount;
      liquidity[toChain] += amount;
      remoteLiquidity += amount;
    }
  }

  function _isEthereumChain(uint256 chainId) internal pure returns (bool) {
    return chainId == 0;
  }

  function _assertInvariant() internal {
    // Check bridged
    assertEq(UpgradeableLockReleaseTokenPool(pools[0]).getCurrentBridgedAmount(), bridged);

    // Check levels and buckets
    uint256 sumLevels;
    uint256 chainId;
    uint256 capacity;
    uint256 level;
    for (uint i = 1; i < chainsList.length; i++) {
      // not counting Ethereum -{0}
      chainId = chainsList[i];
      (capacity, level) = GhoToken(tokens[chainId]).getFacilitatorBucket(pools[chainId]);

      // Aggregate levels
      sumLevels += level;

      assertEq(capacity, bucketCapacities[chainId], "wrong bucket capacity");
      assertEq(level, bucketLevels[chainId], "wrong bucket level");

      assertEq(
        capacity,
        UpgradeableLockReleaseTokenPool(pools[0]).getBridgeLimit(),
        "capacity must be equal to bridgeLimit"
      );
      assertLe(
        level,
        UpgradeableLockReleaseTokenPool(pools[0]).getBridgeLimit(),
        "level cannot be higher than bridgeLimit"
      );
    }
    // Check bridged is equal to sum of levels
    assertEq(UpgradeableLockReleaseTokenPool(pools[0]).getCurrentBridgedAmount(), sumLevels, "wrong bridged");
    assertEq(remoteLiquidity, sumLevels, "wrong bridged");
  }
}
