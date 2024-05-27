// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";

import {BaseTest} from "../../BaseTest.t.sol";
import {IPool} from "../../../interfaces/pools/IPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {GhoBaseTest} from "./GhoBaseTest.t.sol";

contract GhoTokenPoolEthereumBridgeLimitSetup is GhoBaseTest {
  UtilsStorage public s;

  function setUp() public virtual override {
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
  }

  function _assertInvariant() internal {
    // Check bridged
    assertEq(UpgradeableLockReleaseTokenPool(s.pools[0]).getCurrentBridgedAmount(), s.bridged);

    // Check levels and buckets
    uint256 sumLevels;
    uint256 chainId;
    uint256 capacity;
    uint256 level;
    for (uint i = 1; i < s.chainsList.length; i++) {
      // not counting Ethereum -{0}
      chainId = s.chainsList[i];
      (capacity, level) = GhoToken(s.tokens[chainId]).getFacilitatorBucket(s.pools[chainId]);

      // Aggregate levels
      sumLevels += level;

      assertEq(capacity, s.bucketCapacities[chainId], "wrong bucket capacity");
      assertEq(level, s.bucketLevels[chainId], "wrong bucket level");

      assertEq(
        capacity,
        UpgradeableLockReleaseTokenPool(s.pools[0]).getBridgeLimit(),
        "capacity must be equal to bridgeLimit"
      );
      assertLe(
        level,
        UpgradeableLockReleaseTokenPool(s.pools[0]).getBridgeLimit(),
        "level cannot be higher than bridgeLimit"
      );
    }
    // Check bridged is equal to sum of levels
    assertEq(UpgradeableLockReleaseTokenPool(s.pools[0]).getCurrentBridgedAmount(), sumLevels, "wrong bridged");
    assertEq(s.remoteLiquidity, sumLevels, "wrong bridged");
  }
}

contract GhoTokenPoolEthereumBridgeLimitSimpleScenario is GhoTokenPoolEthereumBridgeLimitSetup {
  function setUp() public virtual override {
    super.setUp();

    // Arbitrum
    _addBridge(s, 1, INITIAL_BRIDGE_LIMIT);
    _enableLane(s, 0, 1);
  }

  function testFuzz_Bridge(uint256 amount) public {
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    amount = bound(amount, 1, maxAmount);

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    deal(s.tokens[0], USER, amount);
    _moveGhoOrigin(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(s, 0), amount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    _moveGhoDestination(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(s, 0), amount);
    assertEq(_getMaxToBridgeOut(s, 1), s.bucketLevels[1]);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - s.bucketLevels[1]);

    _assertInvariant();
  }

  function testBridgeAll() public {
    _assertInvariant();

    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    deal(s.tokens[0], USER, maxAmount);
    _moveGhoOrigin(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), maxAmount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    _moveGhoDestination(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), maxAmount);
    assertEq(_getMaxToBridgeOut(s, 1), s.bucketCapacities[1]);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    _assertInvariant();
  }

  /// @dev Bridge out two times
  function testFuzz_BridgeTwoSteps(uint256 amount1, uint256 amount2) public {
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    amount1 = bound(amount1, 1, maxAmount);
    amount2 = bound(amount2, 1, maxAmount);

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    deal(s.tokens[0], USER, amount1);
    _moveGhoOrigin(s, 0, 1, USER, amount1);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount1);
    assertEq(_getMaxToBridgeIn(s, 0), amount1);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    _moveGhoDestination(s, 0, 1, USER, amount1);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount1);
    assertEq(_getMaxToBridgeIn(s, 0), amount1);
    assertEq(_getMaxToBridgeOut(s, 1), s.bucketLevels[1]);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - s.bucketLevels[1]);

    _assertInvariant();

    // Bridge up to bridge limit amount
    if (amount1 + amount2 > maxAmount) {
      vm.expectRevert();
      vm.prank(RAMP);
      IPool(s.pools[0]).lockOrBurn(USER, bytes(""), amount2, uint64(1), bytes(""));

      amount2 = maxAmount - amount1;
    }

    if (amount2 > 0) {
      _assertInvariant();

      uint256 acc = amount1 + amount2;
      deal(s.tokens[0], USER, amount2);
      _moveGhoOrigin(s, 0, 1, USER, amount2);

      assertEq(_getMaxToBridgeOut(s, 0), maxAmount - acc);
      assertEq(_getMaxToBridgeIn(s, 0), acc);
      assertEq(_getMaxToBridgeOut(s, 1), amount1);
      assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - amount1);

      _moveGhoDestination(s, 0, 1, USER, amount2);

      assertEq(_getMaxToBridgeOut(s, 0), maxAmount - acc);
      assertEq(_getMaxToBridgeIn(s, 0), acc);
      assertEq(_getMaxToBridgeOut(s, 1), acc);
      assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - acc);

      _assertInvariant();
    }
  }

  /// @dev Bridge some tokens out and later, bridge them back in
  function testFuzz_BridgeBackAndForth(uint256 amountOut, uint256 amountIn) public {
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    amountOut = bound(amountOut, 1, maxAmount);
    amountIn = bound(amountIn, 1, _getCapacity(s, 1));

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    deal(s.tokens[0], USER, amountOut);
    _moveGhoOrigin(s, 0, 1, USER, amountOut);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amountOut);
    assertEq(_getMaxToBridgeIn(s, 0), amountOut);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);

    _moveGhoDestination(s, 0, 1, USER, amountOut);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amountOut);
    assertEq(_getMaxToBridgeIn(s, 0), amountOut);
    assertEq(_getMaxToBridgeOut(s, 1), s.bucketLevels[1]);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - s.bucketLevels[1]);

    _assertInvariant();

    // Bridge up to current bridged amount
    if (amountIn > amountOut) {
      // Simulate revert on destination
      vm.expectRevert();
      vm.prank(RAMP);
      IPool(s.pools[0]).releaseOrMint(bytes(""), USER, amountIn, uint64(1), bytes(""));

      amountIn = amountOut;
    }

    if (amountIn > 0) {
      _assertInvariant();

      uint256 acc = amountOut - amountIn;
      deal(s.tokens[1], USER, amountIn);
      _moveGhoOrigin(s, 1, 0, USER, amountIn);

      assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amountOut);
      assertEq(_getMaxToBridgeIn(s, 0), amountOut);
      assertEq(_getMaxToBridgeOut(s, 1), acc);
      assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - acc);

      _moveGhoDestination(s, 1, 0, USER, amountIn);

      assertEq(_getMaxToBridgeOut(s, 0), maxAmount - acc);
      assertEq(_getMaxToBridgeIn(s, 0), acc);
      assertEq(_getMaxToBridgeOut(s, 1), acc);
      assertEq(_getMaxToBridgeIn(s, 1), maxAmount - acc);

      _assertInvariant();
    }
  }

  /// @dev Bridge from Ethereum to Arbitrum reverts if amount is higher than bridge limit
  function testFuzz_BridgeBridgeLimitExceededSourceReverts(uint256 amount, uint256 bridgeAmount) public {
    vm.assume(amount < type(uint128).max);
    vm.assume(bridgeAmount < INITIAL_BRIDGE_LIMIT);

    // Inflate bridgeAmount
    if (bridgeAmount > 0) {
      deal(s.tokens[0], USER, bridgeAmount);
      _bridgeGho(s, 0, 1, USER, bridgeAmount);
    }

    deal(s.tokens[0], USER, amount);
    // Simulate CCIP pull of funds
    vm.startPrank(USER);
    GhoToken(s.tokens[0]).transfer(s.pools[0], amount);

    if (bridgeAmount + amount > INITIAL_BRIDGE_LIMIT) {
      vm.expectRevert();
    }
    vm.startPrank(RAMP);
    IPool(s.pools[0]).lockOrBurn(USER, bytes(""), amount, uint64(1), bytes(""));
  }

  /// @dev Bridge from Ethereum to Arbitrum reverts if amount is higher than capacity available
  function testFuzz_BridgeCapacityExceededDestinationReverts(uint256 amount, uint256 level) public {
    (uint256 capacity, ) = GhoToken(s.tokens[1]).getFacilitatorBucket(s.pools[1]);
    vm.assume(level < capacity);
    amount = bound(amount, 1, type(uint128).max);

    // Inflate level
    if (level > 0) {
      _inflateFacilitatorLevel(s.pools[1], s.tokens[1], level);
    }

    // Skip origin move

    // Destination execution
    if (amount > capacity - level) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(s.pools[1]).releaseOrMint(bytes(""), USER, amount, uint64(0), bytes(""));
  }

  /// @dev Bridge from Arbitrum To Ethereum reverts if Arbitrum level is lower than amount
  function testFuzz_BridgeBackZeroLevelSourceReverts(uint256 amount, uint256 level) public {
    (uint256 capacity, ) = GhoToken(s.tokens[1]).getFacilitatorBucket(s.pools[1]);
    vm.assume(level < capacity);
    amount = bound(amount, 1, capacity - level);

    // Inflate level
    if (level > 0) {
      _inflateFacilitatorLevel(s.pools[1], s.tokens[1], level);
    }

    deal(s.tokens[1], USER, amount);
    // Simulate CCIP pull of funds
    vm.prank(USER);
    GhoToken(s.tokens[1]).transfer(s.pools[1], amount);

    if (amount > level) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(s.pools[1]).lockOrBurn(USER, bytes(""), amount, uint64(0), bytes(""));
  }

  /// @dev Bridge from Arbitrum To Ethereum reverts if Ethereum current bridged amount is lower than amount
  function testFuzz_BridgeBackZeroBridgeLimitDestinationReverts(uint256 amount, uint256 bridgeAmount) public {
    (uint256 capacity, ) = GhoToken(s.tokens[1]).getFacilitatorBucket(s.pools[1]);
    amount = bound(amount, 1, capacity);
    bridgeAmount = bound(bridgeAmount, 0, capacity - amount);

    // Inflate bridgeAmount
    if (bridgeAmount > 0) {
      deal(s.tokens[0], USER, bridgeAmount);
      _bridgeGho(s, 0, 1, USER, bridgeAmount);
    }

    // Inflate level on Arbitrum
    _inflateFacilitatorLevel(s.pools[1], s.tokens[1], amount);

    // Skip origin move

    // Destination execution
    if (amount > bridgeAmount) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(s.pools[0]).releaseOrMint(bytes(""), USER, amount, uint64(1), bytes(""));
  }

  /// @dev Bucket capacity reduction. Caution: bridge limit reduction must happen first
  function testReduceBucketCapacity() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, maxAmount);
    _bridgeGho(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(s, 1), 0);
    assertEq(_getCapacity(s, 1), maxAmount);
    assertEq(_getLevel(s, 1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] - 10;
    // 1. Reduce bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    // 2. Reduce bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    // Maximum to bridge in is all minted on Arbitrum
    assertEq(_getMaxToBridgeIn(s, 0), maxAmount);
    assertEq(_getMaxToBridgeOut(s, 1), maxAmount);

    _bridgeGho(s, 1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), newBucketCapacity);

    _assertInvariant();
  }

  /// @dev Bucket capacity reduction, performed following wrong order procedure
  function testReduceBucketCapacityIncorrectProcedure() public {
    // Bridge a third of the capacity
    uint256 amount = _getMaxToBridgeOut(s, 0) / 3;
    uint256 availableToBridge = _getMaxToBridgeOut(s, 0) - amount;

    deal(s.tokens[0], USER, amount);
    _bridgeGho(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - amount);
    assertEq(_getLevel(s, 1), amount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] - 10;
    /// @dev INCORRECT ORDER PROCEDURE!! bridge limit reduction should happen first
    // 1. Reduce bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), availableToBridge); // this is the UX issue
    assertEq(_getMaxToBridgeIn(s, 1), availableToBridge - 10);

    // User can come and try to max bridge on Arbitrum
    // Transaction will succeed on Ethereum, but revert on Arbitrum
    deal(s.tokens[0], USER, availableToBridge);
    _moveGhoOrigin(s, 0, 1, USER, availableToBridge);
    assertEq(_getMaxToBridgeOut(s, 0), 0);

    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[1]).releaseOrMint(bytes(""), USER, availableToBridge, uint64(0), bytes(""));

    // User can only bridge up to new bucket capacity (10 units less)
    assertEq(_getMaxToBridgeIn(s, 1), availableToBridge - 10);
    vm.prank(RAMP);
    IPool(s.pools[1]).releaseOrMint(bytes(""), USER, availableToBridge - 10, uint64(0), bytes(""));
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    // 2. Reduce bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 1), 0);
  }

  /// @dev Bucket capacity reduction, with a bridge out in between
  function testReduceBucketCapacityWithBridgeOutInBetween() public {
    // Bridge a third of the capacity
    uint256 amount = _getMaxToBridgeOut(s, 0) / 3;
    uint256 availableToBridge = _getMaxToBridgeOut(s, 0) - amount;

    deal(s.tokens[0], USER, amount);
    _bridgeGho(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - amount);
    assertEq(_getLevel(s, 1), amount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] - 10;
    // 1. Reduce bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), availableToBridge - 10);
    assertEq(_getMaxToBridgeIn(s, 1), availableToBridge);

    // User initiates bridge out action
    uint256 amount2 = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, amount2);
    _moveGhoOrigin(s, 0, 1, USER, amount2);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), newBucketCapacity);

    // 2. Reduce bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    // Destination execution can happen, no more bridge out actions can be initiated
    assertEq(_getMaxToBridgeOut(s, 1), amount);
    assertEq(_getMaxToBridgeIn(s, 1), amount2);

    // Finalize bridge out action
    _moveGhoDestination(s, 0, 1, USER, amount2);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    _assertInvariant();
  }

  /// @dev Bucket capacity reduction, with a bridge in in between
  function testReduceBucketCapacityWithBridgeInInBetween() public {
    // Bridge max amount
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);

    deal(s.tokens[0], USER, maxAmount);
    _bridgeGho(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(s, 1), 0);
    assertEq(_getCapacity(s, 1), maxAmount);
    assertEq(_getLevel(s, 1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] - 10;
    // 1. Reduce bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    // User initiates bridge in action
    _moveGhoOrigin(s, 1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), maxAmount);

    // 2. Reduce bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), maxAmount);

    // Finalize bridge in action
    _moveGhoDestination(s, 1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), newBucketCapacity);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase. Caution: bridge limit increase must happen afterwards
  function testIncreaseBucketCapacity() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, maxAmount);
    _bridgeGho(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(s, 1), 0);
    assertEq(_getCapacity(s, 1), maxAmount);
    assertEq(_getLevel(s, 1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] + 10;
    // 2. Increase bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 1), 10);

    // Reverts if a user tries to bridge out 10
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[0]).lockOrBurn(USER, bytes(""), 10, uint64(1), bytes(""));

    // 2. Increase bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 10);
    assertEq(_getMaxToBridgeIn(s, 1), 10);

    _assertInvariant();

    // Now it is possible to bridge some again
    _bridgeGho(s, 1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), newBucketCapacity);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase, performed following wrong order procedure
  function testIncreaseBucketCapacityIncorrectProcedure() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, maxAmount);
    _bridgeGho(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(s, 1), 0);
    assertEq(_getCapacity(s, 1), maxAmount);
    assertEq(_getLevel(s, 1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] + 10;

    /// @dev INCORRECT ORDER PROCEDURE!! bucket capacity increase should happen first
    // 1. Increase bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 10);
    assertEq(_getMaxToBridgeIn(s, 1), 0); // this is the UX issue

    // User can come and try to max bridge on Arbitrum
    // Transaction will succeed on Ethereum, but revert on Arbitrum
    deal(s.tokens[0], USER, 10);
    _moveGhoOrigin(s, 0, 1, USER, 10);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), newBucketCapacity);

    // Execution on destination will revert until bucket capacity gets increased
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[1]).releaseOrMint(bytes(""), USER, 10, uint64(0), bytes(""));

    // 2. Increase bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 1), maxAmount);
    assertEq(_getMaxToBridgeIn(s, 1), 10);

    // Now it is possible to execute on destination
    _moveGhoDestination(s, 0, 1, USER, 10);

    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase, with a bridge out in between
  function testIncreaseBucketCapacityWithBridgeOutInBetween() public {
    // Bridge a third of the capacity
    uint256 amount = _getMaxToBridgeOut(s, 0) / 3;
    uint256 availableToBridge = _getMaxToBridgeOut(s, 0) - amount;
    deal(s.tokens[0], USER, amount);
    _bridgeGho(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - amount);
    assertEq(_getLevel(s, 1), amount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] + 10;
    // 1. Increase bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), availableToBridge);
    assertEq(_getMaxToBridgeIn(s, 1), availableToBridge + 10);

    // Reverts if a user tries to bridge out all up to new bucket capacity
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[0]).lockOrBurn(USER, bytes(""), availableToBridge + 10, uint64(1), bytes(""));

    // User initiates bridge out action
    deal(s.tokens[0], USER, availableToBridge);
    _bridgeGho(s, 0, 1, USER, availableToBridge);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 1), 10);

    // 2. Increase bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 10);
    assertEq(_getMaxToBridgeIn(s, 1), 10);

    _assertInvariant();

    // Now it is possible to bridge some again
    deal(s.tokens[0], USER, 10);
    _bridgeGho(s, 0, 1, USER, 10);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase, with a bridge in in between
  function testIncreaseBucketCapacityWithBridgeInInBetween() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, maxAmount);
    _bridgeGho(s, 0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(s, 1), 0);
    assertEq(_getCapacity(s, 1), maxAmount);
    assertEq(_getLevel(s, 1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = s.bucketCapacities[1] + 10;
    // 1. Increase bucket capacity
    _updateBucketCapacity(s, 1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), maxAmount);
    assertEq(_getMaxToBridgeOut(s, 1), maxAmount);
    assertEq(_getMaxToBridgeIn(s, 1), 10);

    // User initiates bridge in action
    _moveGhoOrigin(s, 1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), newBucketCapacity);

    // 2. Increase bridge limit
    _updateBridgeLimit(s, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 10);
    assertEq(_getMaxToBridgeIn(s, 0), maxAmount);

    // User finalizes bridge in action
    _moveGhoDestination(s, 1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 0), 0);

    _assertInvariant();

    // Now it is possible to bridge new bucket capacity
    deal(s.tokens[0], USER, newBucketCapacity);
    _bridgeGho(s, 0, 1, USER, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    assertEq(_getMaxToBridgeIn(s, 0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(s, 1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(s, 1), 0);

    _assertInvariant();
  }
}

contract GhoTokenPoolEthereumBridgeLimitTripleScenario is GhoTokenPoolEthereumBridgeLimitSetup {
  function setUp() public virtual override {
    super.setUp();

    // Arbitrum
    _addBridge(s, 1, INITIAL_BRIDGE_LIMIT);
    _enableLane(s, 0, 1);

    // Avalanche
    _addBridge(s, 2, INITIAL_BRIDGE_LIMIT);
    _enableLane(s, 1, 2);
    _enableLane(s, 0, 2);
  }

  /// @dev Bridge out some tokens to third chain via second chain (Ethereum to Arbitrum, Arbitrum to Avalanche)
  function testFuzz_BridgeToTwoToThree(uint256 amount) public {
    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    amount = bound(amount, 1, maxAmount);

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount);
    assertEq(_getMaxToBridgeIn(s, 0), 0);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(s, 2), 0);
    assertEq(_getMaxToBridgeIn(s, 2), s.bucketCapacities[2]);

    deal(s.tokens[0], USER, amount);
    _moveGhoOrigin(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(s, 0), amount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(s, 2), 0);
    assertEq(_getMaxToBridgeIn(s, 2), s.bucketCapacities[2]);

    _moveGhoDestination(s, 0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(s, 0), amount);
    assertEq(_getMaxToBridgeOut(s, 1), amount);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1] - s.bucketLevels[1]);
    assertEq(_getMaxToBridgeOut(s, 2), 0);
    assertEq(_getMaxToBridgeIn(s, 2), s.bucketCapacities[2]);

    _assertInvariant();

    _moveGhoOrigin(s, 1, 2, USER, amount);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(s, 0), amount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(s, 2), 0);
    assertEq(_getMaxToBridgeIn(s, 2), s.bucketCapacities[2]);

    _moveGhoDestination(s, 1, 2, USER, amount);

    assertEq(_getMaxToBridgeOut(s, 0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(s, 0), amount);
    assertEq(_getMaxToBridgeOut(s, 1), 0);
    assertEq(_getMaxToBridgeIn(s, 1), s.bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(s, 2), amount);
    assertEq(_getMaxToBridgeIn(s, 2), s.bucketCapacities[2] - amount);

    _assertInvariant();
  }

  /// @dev Bridge out some tokens to second and third chain randomly
  function testFuzz_BridgeRandomlyToTwoAndThree(uint64[] memory amounts) public {
    vm.assume(amounts.length < 30);

    uint256 maxAmount = _getMaxToBridgeOut(s, 0);
    uint256 sourceAcc;
    uint256 amount;
    uint256 dest;
    bool lastTime;
    for (uint256 i = 0; i < amounts.length && !lastTime; i++) {
      amount = amounts[i];

      if (amount == 0) amount += 1;
      if (sourceAcc + amount > maxAmount) {
        amount = maxAmount - sourceAcc;
        lastTime = true;
      }

      dest = (amount % 2) + 1;
      deal(s.tokens[0], USER, amount);
      _bridgeGho(s, 0, dest, USER, amount);

      sourceAcc += amount;
    }
    assertEq(sourceAcc, s.bridged);

    // Bridge all to Avalanche
    uint256 toBridge = _getMaxToBridgeOut(s, 1);
    if (toBridge > 0) {
      _bridgeGho(s, 1, 2, USER, toBridge);
      assertEq(sourceAcc, s.bridged);
      assertEq(_getLevel(s, 2), s.bridged);
      assertEq(_getLevel(s, 1), 0);
    }
  }

  /// @dev All remote liquidity is on one chain or the other
  function testLiquidityUnbalanced() public {
    // Bridge all out to Arbitrum
    uint256 amount = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, amount);
    _bridgeGho(s, 0, 1, USER, amount);

    // No more liquidity can go remotely
    assertEq(_getMaxToBridgeOut(s, 0), 0);
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[0]).lockOrBurn(USER, bytes(""), 1, uint64(1), bytes(""));
    vm.prank(RAMP);
    vm.expectRevert();
    IPool(s.pools[0]).lockOrBurn(USER, bytes(""), 1, uint64(2), bytes(""));

    // All liquidity on Arbitrum, 0 on Avalanche
    assertEq(_getLevel(s, 1), s.bridged);
    assertEq(_getLevel(s, 1), _getCapacity(s, 1));
    assertEq(_getLevel(s, 2), 0);

    // Move all liquidity to Avalanche
    _bridgeGho(s, 1, 2, USER, amount);
    assertEq(_getLevel(s, 1), 0);
    assertEq(_getLevel(s, 2), s.bridged);
    assertEq(_getLevel(s, 2), _getCapacity(s, 2));

    // Move all liquidity back to Ethereum
    _bridgeGho(s, 2, 0, USER, amount);
    assertEq(_getLevel(s, 1), 0);
    assertEq(_getLevel(s, 2), 0);
    assertEq(s.bridged, 0);
    assertEq(_getMaxToBridgeOut(s, 0), amount);
  }

  /// @dev Test showcasing incorrect bridge limit and bucket capacity configuration
  function testIncorrectBridgeLimitBucketConfig() public {
    // BridgeLimit 10, Arbitrum 9, Avalanche Bucket 10
    _updateBridgeLimit(s, 10);
    _updateBucketCapacity(s, 1, 9);
    _updateBucketCapacity(s, 2, 10);

    assertEq(_getMaxToBridgeOut(s, 0), 10);
    assertEq(_getMaxToBridgeIn(s, 1), 9); // here the issue
    assertEq(_getMaxToBridgeIn(s, 2), 10);

    // Possible to bridge 10 out to 2
    deal(s.tokens[0], USER, 10);
    _bridgeGho(s, 0, 2, USER, 10);

    // Liquidity comes back
    _bridgeGho(s, 2, 0, USER, 10);

    // Not possible to bridge 10 out to 1
    _moveGhoOrigin(s, 0, 1, USER, 10);
    // Reverts on destination
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[1]).releaseOrMint(bytes(""), USER, 10, uint64(0), bytes(""));

    // Only if bucket capacity gets increased, execution can succeed
    _updateBucketCapacity(s, 1, 10);
    _moveGhoDestination(s, 0, 1, USER, 10);
  }

  /// @dev Test showcasing a user locked due to a bridge limit reduction below current bridged amount
  function testUserLockedBridgeLimitReductionBelowLevel() public {
    // Bridge all out to Arbitrum
    uint256 amount = _getMaxToBridgeOut(s, 0);
    deal(s.tokens[0], USER, amount);
    _bridgeGho(s, 0, 1, USER, amount);

    // Reduce bridge limit below current bridged amount
    uint256 newBridgeLimit = amount / 2;
    _updateBridgeLimit(s, newBridgeLimit);
    _updateBucketCapacity(s, 1, newBridgeLimit);

    // Moving to Avalanche is not a problem because bucket capacity is higher than bridge limit
    assertGt(_getMaxToBridgeIn(s, 2), newBridgeLimit);
    _bridgeGho(s, 1, 2, USER, amount);

    // Moving back to Arbitrum reverts on destination
    assertEq(_getMaxToBridgeIn(s, 1), newBridgeLimit);
    _moveGhoOrigin(s, 2, 1, USER, amount);
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(s.pools[1]).releaseOrMint(bytes(""), USER, amount, uint64(2), bytes(""));
  }
}
