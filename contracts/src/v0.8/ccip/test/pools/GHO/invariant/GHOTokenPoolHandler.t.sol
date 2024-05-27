// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";

import {IPool} from "../../../../interfaces/pools/IPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableTokenPool} from "../../../../pools/GHO/UpgradeableTokenPool.sol";
import {RateLimiter} from "../../../../libraries/RateLimiter.sol";
import {BaseTest} from "../../../BaseTest.t.sol";

contract GHOTokenPoolHandler is BaseTest {
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
  bool public capacityBelowLevelUpdate;

  constructor() {
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

    // Arbitrum
    _addBridge(1, INITIAL_BRIDGE_LIMIT);
    _enableLane(0, 1);

    // Avalanche
    _addBridge(2, INITIAL_BRIDGE_LIMIT);
    _enableLane(0, 2);
    _enableLane(1, 2);
  }

  /// forge-config: ccip.fuzz.runs = 500
  function bridgeGho(uint256 fromChain, uint256 toChain, uint256 amount) public {
    fromChain = bound(fromChain, 0, 2);
    toChain = bound(toChain, 0, 2);
    vm.assume(fromChain != toChain);
    uint256 maxBalance = GhoToken(tokens[fromChain]).balanceOf(address(this));
    uint256 maxToBridge = _getMaxToBridgeOut(fromChain);
    uint256 maxAmount = maxBalance > maxToBridge ? maxToBridge : maxBalance;
    amount = bound(amount, 0, maxAmount);

    if (amount > 0) {
      _bridgeGho(fromChain, toChain, address(this), amount);
    }
  }

  /// forge-config: ccip.fuzz.runs = 500
  function updateBucketCapacity(uint256 chain, uint128 newCapacity) public {
    chain = bound(chain, 1, 2);
    uint256 otherChain = (chain % 2) + 1;
    vm.assume(newCapacity >= bridged);

    uint256 oldCapacity = bucketCapacities[chain];

    if (newCapacity < bucketLevels[chain]) {
      capacityBelowLevelUpdate = true;
    } else {
      capacityBelowLevelUpdate = false;
    }

    if (newCapacity > oldCapacity) {
      // Increase
      _updateBucketCapacity(chain, newCapacity);
      // keep bridge limit as the minimum bucket capacity
      if (newCapacity < bucketCapacities[otherChain]) {
        _updateBridgeLimit(newCapacity);
      }
    } else {
      // Reduction
      // keep bridge limit as the minimum bucket capacity
      if (newCapacity < bucketCapacities[otherChain]) {
        _updateBridgeLimit(newCapacity);
      }
      _updateBucketCapacity(chain, newCapacity);
    }
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
    vm.stopPrank();
    vm.startPrank(OWNER);
    UpgradeableLockReleaseTokenPool(pools[0]).setBridgeLimit(newBridgeLimit);
    vm.stopPrank();
  }

  function _updateBucketCapacity(uint256 chainId, uint256 newBucketCapacity) internal {
    bucketCapacities[chainId] = newBucketCapacity;
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    GhoToken(tokens[chainId]).grantRole(GhoToken(tokens[chainId]).BUCKET_MANAGER_ROLE(), AAVE_DAO);
    GhoToken(tokens[chainId]).setFacilitatorBucketCapacity(pools[chainId], uint128(newBucketCapacity));
    vm.stopPrank();
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

  function _bridgeGho(uint256 fromChain, uint256 toChain, address user, uint256 amount) internal {
    _moveGhoOrigin(fromChain, toChain, user, amount);
    _moveGhoDestination(fromChain, toChain, user, amount);
  }

  function _moveGhoOrigin(uint256 fromChain, uint256 toChain, address user, uint256 amount) internal {
    // Simulate CCIP pull of funds
    vm.startPrank(user);
    GhoToken(tokens[fromChain]).transfer(pools[fromChain], amount);

    vm.startPrank(RAMP);
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
    vm.startPrank(RAMP);
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

  function getChainsList() public view returns (uint256[] memory) {
    return chainsList;
  }
}
