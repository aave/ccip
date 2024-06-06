// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";

import {UpgradeableLockReleaseTokenPool} from "../../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {BaseTest} from "../../../BaseTest.t.sol";
import {GhoTokenPoolHandler} from "./GhoTokenPoolHandler.t.sol";

contract GhoTokenPoolEthereumBridgeLimitInvariant is BaseTest {
  GhoTokenPoolHandler handler;

  function setUp() public override {
    super.setUp();

    handler = new GhoTokenPoolHandler();
    deal(handler.tokens(0), address(handler), handler.INITIAL_BRIDGE_LIMIT());

    targetContract(address(handler));
    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = GhoTokenPoolHandler.bridgeGho.selector;
    selectors[1] = GhoTokenPoolHandler.updateBucketCapacity.selector;
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// forge-config: ccip.invariant.fail-on-revert = true
  /// forge-config: ccip.invariant.runs = 2000
  /// forge-config: ccip.invariant.depth = 50
  function invariant_bridgeLimit() public {
    // Check bridged
    assertEq(UpgradeableLockReleaseTokenPool(handler.pools(0)).getCurrentBridgedAmount(), handler.bridged());

    // Check levels and buckets
    uint256 sumLevels;
    uint256 chainId;
    uint256 capacity;
    uint256 level;
    uint256[] memory chainsListLocal = handler.getChainsList();
    for (uint i = 1; i < chainsListLocal.length; i++) {
      // not counting Ethereum -{0}
      chainId = chainsListLocal[i];
      (capacity, level) = GhoToken(handler.tokens(chainId)).getFacilitatorBucket(handler.pools(chainId));

      // Aggregate levels
      sumLevels += level;

      assertEq(capacity, handler.bucketCapacities(chainId), "wrong bucket capacity");
      assertEq(level, handler.bucketLevels(chainId), "wrong bucket level");

      assertGe(
        capacity,
        UpgradeableLockReleaseTokenPool(handler.pools(0)).getBridgeLimit(),
        "capacity must be equal to bridgeLimit"
      );

      // This invariant only holds if there were no bridge limit reductions below the current bridged amount
      if (!handler.capacityBelowLevelUpdate()) {
        assertLe(
          level,
          UpgradeableLockReleaseTokenPool(handler.pools(0)).getBridgeLimit(),
          "level cannot be higher than bridgeLimit"
        );
      }
    }
    // Check bridged is equal to sum of levels
    assertEq(UpgradeableLockReleaseTokenPool(handler.pools(0)).getCurrentBridgedAmount(), sumLevels, "wrong bridged");
    assertEq(handler.remoteLiquidity(), sumLevels, "wrong bridged");
  }
}
