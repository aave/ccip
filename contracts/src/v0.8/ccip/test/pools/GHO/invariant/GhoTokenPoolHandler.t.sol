// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";

import {IPool} from "../../../../interfaces/pools/IPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableTokenPool} from "../../../../pools/GHO/UpgradeableTokenPool.sol";
import {RateLimiter} from "../../../../libraries/RateLimiter.sol";
import {BaseTest} from "../../../BaseTest.t.sol";
import {GhoBaseTest} from "../GhoBaseTest.t.sol";

contract GhoTokenPoolHandler is GhoBaseTest {
  UtilsStorage public s;

  constructor() {
    // Ethereum with id 0
    s.chainsList.push(0);
    s.tokens[0] = address(new GhoToken(AAVE_DAO));
    s.pools[0] = _deployUpgradeableLockReleaseTokenPool(
      s.tokens[0],
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
    _addBridge(s, 1, INITIAL_BRIDGE_LIMIT);
    _enableLane(s, 0, 1);

    // Avalanche
    _addBridge(s, 2, INITIAL_BRIDGE_LIMIT);
    _enableLane(s, 0, 2);
    _enableLane(s, 1, 2);
  }

  /// forge-config: ccip.fuzz.runs = 500
  function bridgeGho(uint256 fromChain, uint256 toChain, uint256 amount) public {
    fromChain = bound(fromChain, 0, 2);
    toChain = bound(toChain, 0, 2);
    if (fromChain != toChain) {
      uint256 maxBalance = GhoToken(s.tokens[fromChain]).balanceOf(address(this));
      uint256 maxToBridge = _getMaxToBridgeOut(s, fromChain);
      uint256 maxAmount = maxBalance > maxToBridge ? maxToBridge : maxBalance;
      amount = bound(amount, 0, maxAmount);

      if (amount > 0) {
        _bridgeGho(s, fromChain, toChain, address(this), amount);
      }
    }
  }

  /// forge-config: ccip.fuzz.runs = 500
  function updateBucketCapacity(uint256 chain, uint128 newCapacity) public {
    chain = bound(chain, 1, 2);
    uint256 otherChain = (chain % 2) + 1;
    newCapacity = uint128(bound(newCapacity, s.bridged, type(uint128).max));

    uint256 oldCapacity = s.bucketCapacities[chain];

    if (newCapacity < s.bucketLevels[chain]) {
      s.capacityBelowLevelUpdate = true;
    } else {
      s.capacityBelowLevelUpdate = false;
    }

    if (newCapacity > oldCapacity) {
      // Increase
      _updateBucketCapacity(s, chain, newCapacity);
      // keep bridge limit as the minimum bucket capacity
      if (newCapacity < s.bucketCapacities[otherChain]) {
        _updateBridgeLimit(s, newCapacity);
      }
    } else {
      // Reduction
      // keep bridge limit as the minimum bucket capacity
      if (newCapacity < s.bucketCapacities[otherChain]) {
        _updateBridgeLimit(s, newCapacity);
      }
      _updateBucketCapacity(s, chain, newCapacity);
    }
  }

  function getChainsList() public view returns (uint256[] memory) {
    return s.chainsList;
  }

  function pools(uint256 i) public view returns (address) {
    return s.pools[i];
  }

  function tokens(uint256 i) public view returns (address) {
    return s.tokens[i];
  }

  function bucketCapacities(uint256 i) public view returns (uint256) {
    return s.bucketCapacities[i];
  }

  function bucketLevels(uint256 i) public view returns (uint256) {
    return s.bucketLevels[i];
  }

  function liquidity(uint256 i) public view returns (uint256) {
    return s.liquidity[i];
  }

  function remoteLiquidity() public view returns (uint256) {
    return s.remoteLiquidity;
  }

  function bridged() public view returns (uint256) {
    return s.bridged;
  }

  function capacityBelowLevelUpdate() public view returns (bool) {
    return s.capacityBelowLevelUpdate;
  }
}
