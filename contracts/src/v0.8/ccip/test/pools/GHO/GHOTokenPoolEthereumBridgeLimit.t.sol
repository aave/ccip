// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";

import {IPool} from "../../../interfaces/pools/IPool.sol";
import {GHOTokenPoolEthereumBridgeLimitSetup} from "./GHOTokenPoolEthereumBridgeLimitSetup.t.sol";

contract GHOTokenPoolEthereumBridgeLimitSimpleScenario is GHOTokenPoolEthereumBridgeLimitSetup {
  function setUp() public virtual override {
    super.setUp();

    // Arbitrum
    _addBridge(1, INITIAL_BRIDGE_LIMIT);
    _enableLane(0, 1);
  }

  function testFuzz_Bridge(uint256 amount) public {
    uint256 maxAmount = _getMaxToBridgeOut(0);
    amount = bound(amount, 1, maxAmount);

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(0), maxAmount);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    deal(tokens[0], USER, amount);
    _moveGhoOrigin(0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(0), amount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    _moveGhoDestination(0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(0), amount);
    assertEq(_getMaxToBridgeOut(1), bucketLevels[1]);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - bucketLevels[1]);

    _assertInvariant();
  }

  function testBridgeAll() public {
    _assertInvariant();

    uint256 maxAmount = _getMaxToBridgeOut(0);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    deal(tokens[0], USER, maxAmount);
    _moveGhoOrigin(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), maxAmount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    _moveGhoDestination(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), maxAmount);
    assertEq(_getMaxToBridgeOut(1), bucketCapacities[1]);
    assertEq(_getMaxToBridgeIn(1), 0);

    _assertInvariant();
  }

  /// @dev Bridge out two times
  function testFuzz_BridgeTwoSteps(uint256 amount1, uint256 amount2) public {
    uint256 maxAmount = _getMaxToBridgeOut(0);
    amount1 = bound(amount1, 1, maxAmount);
    amount2 = bound(amount2, 1, maxAmount);

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(0), maxAmount);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    deal(tokens[0], USER, amount1);
    _moveGhoOrigin(0, 1, USER, amount1);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount1);
    assertEq(_getMaxToBridgeIn(0), amount1);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    _moveGhoDestination(0, 1, USER, amount1);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount1);
    assertEq(_getMaxToBridgeIn(0), amount1);
    assertEq(_getMaxToBridgeOut(1), bucketLevels[1]);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - bucketLevels[1]);

    _assertInvariant();

    // Bridge up to bridge limit amount
    if (amount1 + amount2 > maxAmount) {
      vm.expectRevert();
      vm.prank(RAMP);
      IPool(pools[0]).lockOrBurn(USER, bytes(""), amount2, uint64(1), bytes(""));

      amount2 = maxAmount - amount1;
    }

    if (amount2 > 0) {
      _assertInvariant();

      uint256 acc = amount1 + amount2;
      deal(tokens[0], USER, amount2);
      _moveGhoOrigin(0, 1, USER, amount2);

      assertEq(_getMaxToBridgeOut(0), maxAmount - acc);
      assertEq(_getMaxToBridgeIn(0), acc);
      assertEq(_getMaxToBridgeOut(1), amount1);
      assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - amount1);

      _moveGhoDestination(0, 1, USER, amount2);

      assertEq(_getMaxToBridgeOut(0), maxAmount - acc);
      assertEq(_getMaxToBridgeIn(0), acc);
      assertEq(_getMaxToBridgeOut(1), acc);
      assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - acc);

      _assertInvariant();
    }
  }

  /// @dev Bridge some tokens out and later, bridge them back in
  function testFuzz_BridgeBackAndForth(uint256 amountOut, uint256 amountIn) public {
    uint256 maxAmount = _getMaxToBridgeOut(0);
    amountOut = bound(amountOut, 1, maxAmount);
    amountIn = bound(amountIn, 1, _getCapacity(1));

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(0), maxAmount);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    deal(tokens[0], USER, amountOut);
    _moveGhoOrigin(0, 1, USER, amountOut);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amountOut);
    assertEq(_getMaxToBridgeIn(0), amountOut);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);

    _moveGhoDestination(0, 1, USER, amountOut);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amountOut);
    assertEq(_getMaxToBridgeIn(0), amountOut);
    assertEq(_getMaxToBridgeOut(1), bucketLevels[1]);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - bucketLevels[1]);

    _assertInvariant();

    // Bridge up to current bridged amount
    if (amountIn > amountOut) {
      // Simulate revert on destination
      vm.expectRevert();
      vm.prank(RAMP);
      IPool(pools[0]).releaseOrMint(bytes(""), USER, amountIn, uint64(1), bytes(""));

      amountIn = amountOut;
    }

    if (amountIn > 0) {
      _assertInvariant();

      uint256 acc = amountOut - amountIn;
      deal(tokens[1], USER, amountIn);
      _moveGhoOrigin(1, 0, USER, amountIn);

      assertEq(_getMaxToBridgeOut(0), maxAmount - amountOut);
      assertEq(_getMaxToBridgeIn(0), amountOut);
      assertEq(_getMaxToBridgeOut(1), acc);
      assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - acc);

      _moveGhoDestination(1, 0, USER, amountIn);

      assertEq(_getMaxToBridgeOut(0), maxAmount - acc);
      assertEq(_getMaxToBridgeIn(0), acc);
      assertEq(_getMaxToBridgeOut(1), acc);
      assertEq(_getMaxToBridgeIn(1), maxAmount - acc);

      _assertInvariant();
    }
  }

  /// @dev Bridge from Ethereum to Arbitrum reverts if amount is higher than bridge limit
  function testFuzz_BridgeBridgeLimitExceededSourceReverts(uint256 amount, uint256 bridgeAmount) public {
    vm.assume(amount < type(uint128).max);
    vm.assume(bridgeAmount < INITIAL_BRIDGE_LIMIT);

    // Inflate bridgeAmount
    if (bridgeAmount > 0) {
      deal(tokens[0], USER, bridgeAmount);
      _bridgeGho(0, 1, USER, bridgeAmount);
    }

    deal(tokens[0], USER, amount);
    // Simulate CCIP pull of funds
    vm.prank(USER);
    GhoToken(tokens[0]).transfer(pools[0], amount);

    if (bridgeAmount + amount > INITIAL_BRIDGE_LIMIT) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(pools[0]).lockOrBurn(USER, bytes(""), amount, uint64(1), bytes(""));
  }

  /// @dev Bridge from Ethereum to Arbitrum reverts if amount is higher than capacity available
  function testFuzz_BridgeCapacityExceededDestinationReverts(uint256 amount, uint256 level) public {
    (uint256 capacity, ) = GhoToken(tokens[1]).getFacilitatorBucket(pools[1]);
    vm.assume(level < capacity);
    amount = bound(amount, 1, type(uint128).max);

    // Inflate level
    if (level > 0) {
      _inflateFacilitatorLevel(pools[1], tokens[1], level);
    }

    // Skip origin move

    // Destination execution
    if (amount > capacity - level) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(pools[1]).releaseOrMint(bytes(""), USER, amount, uint64(0), bytes(""));
  }

  /// @dev Bridge from Arbitrum To Ethereum reverts if Arbitrum level is lower than amount
  function testFuzz_BridgeBackZeroLevelSourceReverts(uint256 amount, uint256 level) public {
    (uint256 capacity, ) = GhoToken(tokens[1]).getFacilitatorBucket(pools[1]);
    vm.assume(level < capacity);
    amount = bound(amount, 1, capacity - level);

    // Inflate level
    if (level > 0) {
      _inflateFacilitatorLevel(pools[1], tokens[1], level);
    }

    deal(tokens[1], USER, amount);
    // Simulate CCIP pull of funds
    vm.prank(USER);
    GhoToken(tokens[1]).transfer(pools[1], amount);

    if (amount > level) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(pools[1]).lockOrBurn(USER, bytes(""), amount, uint64(0), bytes(""));
  }

  /// @dev Bridge from Arbitrum To Ethereum reverts if Ethereum current bridged amount is lower than amount
  function testFuzz_BridgeBackZeroBridgeLimitDestinationReverts(uint256 amount, uint256 bridgeAmount) public {
    (uint256 capacity, ) = GhoToken(tokens[1]).getFacilitatorBucket(pools[1]);
    amount = bound(amount, 1, capacity);
    bridgeAmount = bound(bridgeAmount, 0, capacity - amount);

    // Inflate bridgeAmount
    if (bridgeAmount > 0) {
      deal(tokens[0], USER, bridgeAmount);
      _bridgeGho(0, 1, USER, bridgeAmount);
    }

    // Inflate level on Arbitrum
    _inflateFacilitatorLevel(pools[1], tokens[1], amount);

    // Skip origin move

    // Destination execution
    if (amount > bridgeAmount) {
      vm.expectRevert();
    }
    vm.prank(RAMP);
    IPool(pools[0]).releaseOrMint(bytes(""), USER, amount, uint64(1), bytes(""));
  }

  /// @dev Bucket capacity reduction. Caution: bridge limit reduction must happen first
  function testReduceBucketCapacity() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, maxAmount);
    _bridgeGho(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(1), 0);
    assertEq(_getCapacity(1), maxAmount);
    assertEq(_getLevel(1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] - 10;
    // 1. Reduce bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(1), 0);

    // 2. Reduce bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(1), 0);

    // Maximum to bridge in is all minted on Arbitrum
    assertEq(_getMaxToBridgeIn(0), maxAmount);
    assertEq(_getMaxToBridgeOut(1), maxAmount);

    _bridgeGho(1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), newBucketCapacity);

    _assertInvariant();
  }

  /// @dev Bucket capacity reduction, performed following wrong order procedure
  function testReduceBucketCapacityIncorrectProcedure() public {
    // Bridge a third of the capacity
    uint256 amount = _getMaxToBridgeOut(0) / 3;
    uint256 availableToBridge = _getMaxToBridgeOut(0) - amount;

    deal(tokens[0], USER, amount);
    _bridgeGho(0, 1, USER, amount);

    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - amount);
    assertEq(_getLevel(1), amount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] - 10;
    /// @dev INCORRECT ORDER PROCEDURE!! bridge limit reduction should happen first
    // 1. Reduce bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), availableToBridge); // this is the UX issue
    assertEq(_getMaxToBridgeIn(1), availableToBridge - 10);

    // User can come and try to max bridge on Arbitrum
    // Transaction will succeed on Ethereum, but revert on Arbitrum
    deal(tokens[0], USER, availableToBridge);
    _moveGhoOrigin(0, 1, USER, availableToBridge);
    assertEq(_getMaxToBridgeOut(0), 0);

    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[1]).releaseOrMint(bytes(""), USER, availableToBridge, uint64(0), bytes(""));

    // User can only bridge up to new bucket capacity (10 units less)
    assertEq(_getMaxToBridgeIn(1), availableToBridge - 10);
    vm.prank(RAMP);
    IPool(pools[1]).releaseOrMint(bytes(""), USER, availableToBridge - 10, uint64(0), bytes(""));
    assertEq(_getMaxToBridgeIn(1), 0);

    // 2. Reduce bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(1), 0);
  }

  /// @dev Bucket capacity reduction, with a bridge out in between
  function testReduceBucketCapacityWithBridgeOutInBetween() public {
    // Bridge a third of the capacity
    uint256 amount = _getMaxToBridgeOut(0) / 3;
    uint256 availableToBridge = _getMaxToBridgeOut(0) - amount;

    deal(tokens[0], USER, amount);
    _bridgeGho(0, 1, USER, amount);

    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - amount);
    assertEq(_getLevel(1), amount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] - 10;
    // 1. Reduce bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), availableToBridge - 10);
    assertEq(_getMaxToBridgeIn(1), availableToBridge);

    // User initiates bridge out action
    uint256 amount2 = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, amount2);
    _moveGhoOrigin(0, 1, USER, amount2);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), newBucketCapacity);

    // 2. Reduce bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    // Destination execution can happen, no more bridge out actions can be initiated
    assertEq(_getMaxToBridgeOut(1), amount);
    assertEq(_getMaxToBridgeIn(1), amount2);

    // Finalize bridge out action
    _moveGhoDestination(0, 1, USER, amount2);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(1), 0);

    _assertInvariant();
  }

  /// @dev Bucket capacity reduction, with a bridge in in between
  function testReduceBucketCapacityWithBridgeInInBetween() public {
    // Bridge max amount
    uint256 maxAmount = _getMaxToBridgeOut(0);

    deal(tokens[0], USER, maxAmount);
    _bridgeGho(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(1), 0);
    assertEq(_getCapacity(1), maxAmount);
    assertEq(_getLevel(1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] - 10;
    // 1. Reduce bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(1), 0);

    // User initiates bridge in action
    _moveGhoOrigin(1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), maxAmount);

    // 2. Reduce bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), maxAmount);

    // Finalize bridge in action
    _moveGhoDestination(1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), newBucketCapacity);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase. Caution: bridge limit increase must happen afterwards
  function testIncreaseBucketCapacity() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, maxAmount);
    _bridgeGho(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(1), 0);
    assertEq(_getCapacity(1), maxAmount);
    assertEq(_getLevel(1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] + 10;
    // 2. Increase bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(1), 10);

    // Reverts if a user tries to bridge out 10
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[0]).lockOrBurn(USER, bytes(""), 10, uint64(1), bytes(""));

    // 2. Increase bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 10);
    assertEq(_getMaxToBridgeIn(1), 10);

    _assertInvariant();

    // Now it is possible to bridge some again
    _bridgeGho(1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), newBucketCapacity);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase, performed following wrong order procedure
  function testIncreaseBucketCapacityIncorrectProcedure() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, maxAmount);
    _bridgeGho(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(1), 0);
    assertEq(_getCapacity(1), maxAmount);
    assertEq(_getLevel(1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] + 10;

    /// @dev INCORRECT ORDER PROCEDURE!! bucket capacity increase should happen first
    // 1. Increase bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 10);
    assertEq(_getMaxToBridgeIn(1), 0); // this is the UX issue

    // User can come and try to max bridge on Arbitrum
    // Transaction will succeed on Ethereum, but revert on Arbitrum
    deal(tokens[0], USER, 10);
    _moveGhoOrigin(0, 1, USER, 10);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), newBucketCapacity);

    // Execution on destination will revert until bucket capacity gets increased
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[1]).releaseOrMint(bytes(""), USER, 10, uint64(0), bytes(""));

    // 2. Increase bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(1), maxAmount);
    assertEq(_getMaxToBridgeIn(1), 10);

    // Now it is possible to execute on destination
    _moveGhoDestination(0, 1, USER, 10);

    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(1), 0);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase, with a bridge out in between
  function testIncreaseBucketCapacityWithBridgeOutInBetween() public {
    // Bridge a third of the capacity
    uint256 amount = _getMaxToBridgeOut(0) / 3;
    uint256 availableToBridge = _getMaxToBridgeOut(0) - amount;
    deal(tokens[0], USER, amount);
    _bridgeGho(0, 1, USER, amount);

    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - amount);
    assertEq(_getLevel(1), amount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] + 10;
    // 1. Increase bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), availableToBridge);
    assertEq(_getMaxToBridgeIn(1), availableToBridge + 10);

    // Reverts if a user tries to bridge out all up to new bucket capacity
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[0]).lockOrBurn(USER, bytes(""), availableToBridge + 10, uint64(1), bytes(""));

    // User initiates bridge out action
    deal(tokens[0], USER, availableToBridge);
    _bridgeGho(0, 1, USER, availableToBridge);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(1), 10);

    // 2. Increase bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 10);
    assertEq(_getMaxToBridgeIn(1), 10);

    _assertInvariant();

    // Now it is possible to bridge some again
    deal(tokens[0], USER, 10);
    _bridgeGho(0, 1, USER, 10);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(1), 0);

    _assertInvariant();
  }

  /// @dev Bucket capacity increase, with a bridge in in between
  function testIncreaseBucketCapacityWithBridgeInInBetween() public {
    // Max out capacity
    uint256 maxAmount = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, maxAmount);
    _bridgeGho(0, 1, USER, maxAmount);

    assertEq(_getMaxToBridgeIn(1), 0);
    assertEq(_getCapacity(1), maxAmount);
    assertEq(_getLevel(1), maxAmount);

    _assertInvariant();

    uint256 newBucketCapacity = bucketCapacities[1] + 10;
    // 1. Increase bucket capacity
    _updateBucketCapacity(1, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), maxAmount);
    assertEq(_getMaxToBridgeOut(1), maxAmount);
    assertEq(_getMaxToBridgeIn(1), 10);

    // User initiates bridge in action
    _moveGhoOrigin(1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), newBucketCapacity);

    // 2. Increase bridge limit
    _updateBridgeLimit(newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 10);
    assertEq(_getMaxToBridgeIn(0), maxAmount);

    // User finalizes bridge in action
    _moveGhoDestination(1, 0, USER, maxAmount);
    assertEq(_getMaxToBridgeOut(0), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(0), 0);

    _assertInvariant();

    // Now it is possible to bridge new bucket capacity
    deal(tokens[0], USER, newBucketCapacity);
    _bridgeGho(0, 1, USER, newBucketCapacity);
    assertEq(_getMaxToBridgeOut(0), 0);
    assertEq(_getMaxToBridgeIn(0), newBucketCapacity);
    assertEq(_getMaxToBridgeOut(1), newBucketCapacity);
    assertEq(_getMaxToBridgeIn(1), 0);

    _assertInvariant();
  }
}

contract GHOTokenPoolEthereumBridgeLimitTripleScenario is GHOTokenPoolEthereumBridgeLimitSetup {
  function setUp() public virtual override {
    super.setUp();

    // Arbitrum
    _addBridge(1, INITIAL_BRIDGE_LIMIT);
    _enableLane(0, 1);

    // Avalanche
    _addBridge(2, INITIAL_BRIDGE_LIMIT);
    _enableLane(1, 2);
    _enableLane(0, 2);
  }

  /// @dev Bridge out some tokens to third chain via second chain (Ethereum to Arbitrum, Arbitrum to Avalanche)
  function testFuzz_BridgeToTwoToThree(uint256 amount) public {
    uint256 maxAmount = _getMaxToBridgeOut(0);
    amount = bound(amount, 1, maxAmount);

    _assertInvariant();

    assertEq(_getMaxToBridgeOut(0), maxAmount);
    assertEq(_getMaxToBridgeIn(0), 0);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(2), 0);
    assertEq(_getMaxToBridgeIn(2), bucketCapacities[2]);

    deal(tokens[0], USER, amount);
    _moveGhoOrigin(0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(0), amount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(2), 0);
    assertEq(_getMaxToBridgeIn(2), bucketCapacities[2]);

    _moveGhoDestination(0, 1, USER, amount);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(0), amount);
    assertEq(_getMaxToBridgeOut(1), amount);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1] - bucketLevels[1]);
    assertEq(_getMaxToBridgeOut(2), 0);
    assertEq(_getMaxToBridgeIn(2), bucketCapacities[2]);

    _assertInvariant();

    _moveGhoOrigin(1, 2, USER, amount);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(0), amount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(2), 0);
    assertEq(_getMaxToBridgeIn(2), bucketCapacities[2]);

    _moveGhoDestination(1, 2, USER, amount);

    assertEq(_getMaxToBridgeOut(0), maxAmount - amount);
    assertEq(_getMaxToBridgeIn(0), amount);
    assertEq(_getMaxToBridgeOut(1), 0);
    assertEq(_getMaxToBridgeIn(1), bucketCapacities[1]);
    assertEq(_getMaxToBridgeOut(2), amount);
    assertEq(_getMaxToBridgeIn(2), bucketCapacities[2] - amount);

    _assertInvariant();
  }

  /// @dev Bridge out some tokens to second and third chain randomly
  function testFuzz_BridgeRandomlyToTwoAndThree(uint64[] memory amounts) public {
    vm.assume(amounts.length < 30);

    uint256 maxAmount = _getMaxToBridgeOut(0);
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
      deal(tokens[0], USER, amount);
      _bridgeGho(0, dest, USER, amount);

      sourceAcc += amount;
    }
    assertEq(sourceAcc, bridged);

    // Bridge all to Avalanche
    uint256 toBridge = _getMaxToBridgeOut(1);
    if (toBridge > 0) {
      _bridgeGho(1, 2, USER, toBridge);
      assertEq(sourceAcc, bridged);
      assertEq(_getLevel(2), bridged);
      assertEq(_getLevel(1), 0);
    }
  }

  /// @dev All remote liquidity is on one chain or the other
  function testLiquidityUnbalanced() public {
    // Bridge all out to Arbitrum
    uint256 amount = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, amount);
    _bridgeGho(0, 1, USER, amount);

    // No more liquidity can go remotely
    assertEq(_getMaxToBridgeOut(0), 0);
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[0]).lockOrBurn(USER, bytes(""), 1, uint64(1), bytes(""));
    vm.prank(RAMP);
    vm.expectRevert();
    IPool(pools[0]).lockOrBurn(USER, bytes(""), 1, uint64(2), bytes(""));

    // All liquidity on Arbitrum, 0 on Avalanche
    assertEq(_getLevel(1), bridged);
    assertEq(_getLevel(1), _getCapacity(1));
    assertEq(_getLevel(2), 0);

    // Move all liquidity to Avalanche
    _bridgeGho(1, 2, USER, amount);
    assertEq(_getLevel(1), 0);
    assertEq(_getLevel(2), bridged);
    assertEq(_getLevel(2), _getCapacity(2));

    // Move all liquidity back to Ethereum
    _bridgeGho(2, 0, USER, amount);
    assertEq(_getLevel(1), 0);
    assertEq(_getLevel(2), 0);
    assertEq(bridged, 0);
    assertEq(_getMaxToBridgeOut(0), amount);
  }

  /// @dev Test showcasing incorrect bridge limit and bucket capacity configuration
  function testIncorrectBridgeLimitBucketConfig() public {
    // BridgeLimit 10, Arbitrum 9, Avalanche Bucket 10
    _updateBridgeLimit(10);
    _updateBucketCapacity(1, 9);
    _updateBucketCapacity(2, 10);

    assertEq(_getMaxToBridgeOut(0), 10);
    assertEq(_getMaxToBridgeIn(1), 9); // here the issue
    assertEq(_getMaxToBridgeIn(2), 10);

    // Possible to bridge 10 out to 2
    deal(tokens[0], USER, 10);
    _bridgeGho(0, 2, USER, 10);

    // Liquidity comes back
    _bridgeGho(2, 0, USER, 10);

    // Not possible to bridge 10 out to 1
    _moveGhoOrigin(0, 1, USER, 10);
    // Reverts on destination
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[1]).releaseOrMint(bytes(""), USER, 10, uint64(0), bytes(""));

    // Only if bucket capacity gets increased, execution can succeed
    _updateBucketCapacity(1, 10);
    _moveGhoDestination(0, 1, USER, 10);
  }

  /// @dev Test showcasing a user locked due to a bridge limit reduction below current bridged amount
  function testUserLockedBridgeLimitReductionBelowLevel() public {
    // Bridge all out to Arbitrum
    uint256 amount = _getMaxToBridgeOut(0);
    deal(tokens[0], USER, amount);
    _bridgeGho(0, 1, USER, amount);

    // Reduce bridge limit below current bridged amount
    uint256 newBridgeLimit = amount / 2;
    _updateBridgeLimit(newBridgeLimit);
    _updateBucketCapacity(1, newBridgeLimit);

    // Moving to Avalanche is not a problem because bucket capacity is higher than bridge limit
    assertGt(_getMaxToBridgeIn(2), newBridgeLimit);
    _bridgeGho(1, 2, USER, amount);

    // Moving back to Arbitrum reverts on destination
    assertEq(_getMaxToBridgeIn(1), newBridgeLimit);
    _moveGhoOrigin(2, 1, USER, amount);
    vm.expectRevert();
    vm.prank(RAMP);
    IPool(pools[1]).releaseOrMint(bytes(""), USER, amount, uint64(2), bytes(""));
  }
}
