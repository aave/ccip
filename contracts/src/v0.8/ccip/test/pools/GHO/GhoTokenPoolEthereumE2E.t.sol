// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import "../../helpers/MerkleHelper.sol";
import "../../commitStore/CommitStore.t.sol";
import "../../onRamp/EVM2EVMOnRampSetup.t.sol";
import "../../offRamp/EVM2EVMOffRampSetup.t.sol";
import {IBurnMintERC20} from "../../../../shared/token/ERC20/IBurnMintERC20.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {IPool} from "../../../interfaces/pools/IPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {BaseTest} from "../../BaseTest.t.sol";
import {E2E} from "../End2End.t.sol";
import {GhoBaseTest} from "./GhoBaseTest.t.sol";

contract GhoTokenPoolEthereumE2E is E2E, GhoBaseTest {
  using Internal for Internal.EVM2EVMMessage;

  IBurnMintERC20 internal srcGhoToken;
  IBurnMintERC20 internal dstGhoToken;
  UpgradeableLockReleaseTokenPool internal srcGhoTokenPool;
  UpgradeableBurnMintTokenPool internal dstGhoTokenPool;

  function setUp() public virtual override(E2E, BaseTest) {
    E2E.setUp();

    // Deploy GHO Token on source chain
    srcGhoToken = IBurnMintERC20(address(new GhoToken(AAVE_DAO)));
    deal(address(srcGhoToken), OWNER, type(uint128).max);
    // Add GHO token to source token list
    s_sourceTokens.push(address(srcGhoToken));

    // Deploy GHO Token on destination chain
    dstGhoToken = IBurnMintERC20(address(new GhoToken(AAVE_DAO)));
    deal(address(dstGhoToken), OWNER, type(uint128).max);
    // Add GHO token to destination token list
    s_destTokens.push(address(dstGhoToken));

    // Deploy LockReleaseTokenPool for GHO token on source chain
    srcGhoTokenPool = UpgradeableLockReleaseTokenPool(
      _deployUpgradeableLockReleaseTokenPool(
        address(srcGhoToken),
        address(s_mockARM),
        address(s_sourceRouter),
        AAVE_DAO,
        INITIAL_BRIDGE_LIMIT,
        PROXY_ADMIN
      )
    );

    // Add GHO UpgradeableTokenPool to source token pool list
    s_sourcePools.push(address(srcGhoTokenPool));

    // Deploy BurnMintTokenPool for GHO token on destination chain
    dstGhoTokenPool = UpgradeableBurnMintTokenPool(
      _deployUpgradeableBurnMintTokenPool(
        address(dstGhoToken),
        address(s_mockARM),
        address(s_destRouter),
        AAVE_DAO,
        PROXY_ADMIN
      )
    );

    // Add GHO UpgradeableTokenPool to destination token pool list
    s_destPools.push(address(dstGhoTokenPool));

    // Give mint and burn privileges to destination UpgradeableTokenPool (GHO-specific related)
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    GhoToken(address(dstGhoToken)).grantRole(GhoToken(address(dstGhoToken)).FACILITATOR_MANAGER_ROLE(), AAVE_DAO);
    GhoToken(address(dstGhoToken)).addFacilitator(address(dstGhoTokenPool), "UpgradeableTokenPool", type(uint128).max);
    vm.stopPrank();
    vm.startPrank(OWNER);

    // Add config for source and destination chains
    UpgradeableTokenPool.ChainUpdate[] memory srcChainUpdates = new UpgradeableTokenPool.ChainUpdate[](1);
    srcChainUpdates[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: DEST_CHAIN_SELECTOR,
      allowed: true,
      outboundRateLimiterConfig: getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: getInboundRateLimiterConfig()
    });
    UpgradeableTokenPool.ChainUpdate[] memory dstChainUpdates = new UpgradeableTokenPool.ChainUpdate[](1);
    dstChainUpdates[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: SOURCE_CHAIN_SELECTOR,
      allowed: true,
      outboundRateLimiterConfig: getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: getInboundRateLimiterConfig()
    });
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    srcGhoTokenPool.applyChainUpdates(srcChainUpdates);
    dstGhoTokenPool.applyChainUpdates(dstChainUpdates);
    vm.stopPrank();
    vm.startPrank(OWNER);

    // Update GHO Token price on source PriceRegistry
    EVM2EVMOnRamp.DynamicConfig memory onRampDynamicConfig = s_onRamp.getDynamicConfig();
    PriceRegistry onRampPriceRegistry = PriceRegistry(onRampDynamicConfig.priceRegistry);
    onRampPriceRegistry.updatePrices(getSingleTokenPriceUpdateStruct(address(srcGhoToken), 1e18));

    // Update GHO Token price on destination PriceRegistry
    EVM2EVMOffRamp.DynamicConfig memory offRampDynamicConfig = s_offRamp.getDynamicConfig();
    PriceRegistry offRampPriceRegistry = PriceRegistry(offRampDynamicConfig.priceRegistry);
    offRampPriceRegistry.updatePrices(getSingleTokenPriceUpdateStruct(address(dstGhoToken), 1e18));

    // Add UpgradeableTokenPool to OnRamp
    address[] memory srcTokens = new address[](1);
    IPool[] memory srcPools = new IPool[](1);
    srcTokens[0] = address(srcGhoToken);
    srcPools[0] = IPool(address(srcGhoTokenPool));
    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), getTokensAndPools(srcTokens, srcPools));

    // Add UpgradeableTokenPool to OffRamp, matching source token with destination UpgradeableTokenPool
    IPool[] memory dstPools = new IPool[](1);
    dstPools[0] = IPool(address(dstGhoTokenPool));
    s_offRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), getTokensAndPools(srcTokens, dstPools));
  }

  function testE2E_MessagesSuccess_gas() public {
    vm.pauseGasMetering();
    uint256 preGhoTokenBalanceOwner = srcGhoToken.balanceOf(OWNER);
    uint256 preGhoTokenBalancePool = srcGhoToken.balanceOf(address(srcGhoTokenPool));
    uint256 preBridgedAmount = srcGhoTokenPool.getCurrentBridgedAmount();
    uint256 preBridgeLimit = srcGhoTokenPool.getBridgeLimit();

    Internal.EVM2EVMMessage[] memory messages = new Internal.EVM2EVMMessage[](1);
    messages[0] = sendRequestGho(1, 1000 * 1e18, false, false);

    uint256 expectedFee = s_sourceRouter.getFee(DEST_CHAIN_SELECTOR, _generateTokenMessage());
    // Asserts that the tokens have been sent and the fee has been paid.
    assertEq(preGhoTokenBalanceOwner - 1000 * 1e18, srcGhoToken.balanceOf(OWNER));
    assertEq(preGhoTokenBalancePool + 1000 * 1e18, srcGhoToken.balanceOf(address(srcGhoTokenPool)));
    assertGt(expectedFee, 0);

    assertEq(preBridgedAmount + 1000 * 1e18, srcGhoTokenPool.getCurrentBridgedAmount());
    assertEq(preBridgeLimit, srcGhoTokenPool.getBridgeLimit());

    bytes32 metaDataHash = s_offRamp.metadataHash();

    bytes32[] memory hashedMessages = new bytes32[](1);
    hashedMessages[0] = messages[0]._hash(metaDataHash);
    messages[0].messageId = hashedMessages[0];

    bytes32[] memory merkleRoots = new bytes32[](1);
    merkleRoots[0] = MerkleHelper.getMerkleRoot(hashedMessages);

    address[] memory onRamps = new address[](1);
    onRamps[0] = ON_RAMP_ADDRESS;

    bytes memory commitReport = abi.encode(
      CommitStore.CommitReport({
        priceUpdates: getEmptyPriceUpdates(),
        interval: CommitStore.Interval(messages[0].sequenceNumber, messages[0].sequenceNumber),
        merkleRoot: merkleRoots[0]
      })
    );

    vm.resumeGasMetering();
    s_commitStore.report(commitReport, ++s_latestEpochAndRound);
    vm.pauseGasMetering();

    bytes32[] memory proofs = new bytes32[](0);
    uint256 timestamp = s_commitStore.verify(merkleRoots, proofs, 2 ** 2 - 1);
    assertEq(BLOCK_TIME, timestamp);

    // We change the block time so when execute would e.g. use the current
    // block time instead of the committed block time the value would be
    // incorrect in the checks below.
    vm.warp(BLOCK_TIME + 2000);

    vm.expectEmit();
    emit ExecutionStateChanged(
      messages[0].sequenceNumber,
      messages[0].messageId,
      Internal.MessageExecutionState.SUCCESS,
      ""
    );

    Internal.ExecutionReport memory execReport = _generateReportFromMessages(messages);

    uint256 preGhoTokenBalanceUser = dstGhoToken.balanceOf(USER);
    (uint256 preCapacity, uint256 preLevel) = GhoToken(address(dstGhoToken)).getFacilitatorBucket(
      address(dstGhoTokenPool)
    );

    vm.resumeGasMetering();
    s_offRamp.execute(execReport, new uint256[](0));
    vm.pauseGasMetering();

    assertEq(preGhoTokenBalanceUser + 1000 * 1e18, dstGhoToken.balanceOf(USER), "Wrong balance on destination");
    // Facilitator checks
    (uint256 postCapacity, uint256 postLevel) = GhoToken(address(dstGhoToken)).getFacilitatorBucket(
      address(dstGhoTokenPool)
    );
    assertEq(postCapacity, preCapacity);
    assertEq(preLevel + 1000 * 1e18, postLevel, "wrong facilitator bucket level");
  }

  function testE2E_3MessagesSuccess_gas() public {
    vm.pauseGasMetering();
    uint256 preGhoTokenBalanceOwner = srcGhoToken.balanceOf(OWNER);
    uint256 preGhoTokenBalancePool = srcGhoToken.balanceOf(address(srcGhoTokenPool));
    uint256 preBridgedAmount = srcGhoTokenPool.getCurrentBridgedAmount();
    uint256 preBridgeLimit = srcGhoTokenPool.getBridgeLimit();

    Internal.EVM2EVMMessage[] memory messages = new Internal.EVM2EVMMessage[](3);
    messages[0] = sendRequestGho(1, 1000 * 1e18, false, false);
    messages[1] = sendRequestGho(2, 2000 * 1e18, false, false);
    messages[2] = sendRequestGho(3, 3000 * 1e18, false, false);

    uint256 expectedFee = s_sourceRouter.getFee(DEST_CHAIN_SELECTOR, _generateTokenMessage());
    // Asserts that the tokens have been sent and the fee has been paid.
    assertEq(preGhoTokenBalanceOwner - 6000 * 1e18, srcGhoToken.balanceOf(OWNER));
    assertEq(preGhoTokenBalancePool + 6000 * 1e18, srcGhoToken.balanceOf(address(srcGhoTokenPool)));
    assertGt(expectedFee, 0);

    assertEq(preBridgedAmount + 6000 * 1e18, srcGhoTokenPool.getCurrentBridgedAmount());
    assertEq(preBridgeLimit, srcGhoTokenPool.getBridgeLimit());

    bytes32 metaDataHash = s_offRamp.metadataHash();

    bytes32[] memory hashedMessages = new bytes32[](3);
    hashedMessages[0] = messages[0]._hash(metaDataHash);
    messages[0].messageId = hashedMessages[0];
    hashedMessages[1] = messages[1]._hash(metaDataHash);
    messages[1].messageId = hashedMessages[1];
    hashedMessages[2] = messages[2]._hash(metaDataHash);
    messages[2].messageId = hashedMessages[2];

    bytes32[] memory merkleRoots = new bytes32[](1);
    merkleRoots[0] = MerkleHelper.getMerkleRoot(hashedMessages);

    address[] memory onRamps = new address[](1);
    onRamps[0] = ON_RAMP_ADDRESS;

    bytes memory commitReport = abi.encode(
      CommitStore.CommitReport({
        priceUpdates: getEmptyPriceUpdates(),
        interval: CommitStore.Interval(messages[0].sequenceNumber, messages[2].sequenceNumber),
        merkleRoot: merkleRoots[0]
      })
    );

    vm.resumeGasMetering();
    s_commitStore.report(commitReport, ++s_latestEpochAndRound);
    vm.pauseGasMetering();

    bytes32[] memory proofs = new bytes32[](0);
    uint256 timestamp = s_commitStore.verify(merkleRoots, proofs, 2 ** 2 - 1);
    assertEq(BLOCK_TIME, timestamp);

    // We change the block time so when execute would e.g. use the current
    // block time instead of the committed block time the value would be
    // incorrect in the checks below.
    vm.warp(BLOCK_TIME + 2000);

    vm.expectEmit();
    emit ExecutionStateChanged(
      messages[0].sequenceNumber,
      messages[0].messageId,
      Internal.MessageExecutionState.SUCCESS,
      ""
    );

    vm.expectEmit();
    emit ExecutionStateChanged(
      messages[1].sequenceNumber,
      messages[1].messageId,
      Internal.MessageExecutionState.SUCCESS,
      ""
    );

    vm.expectEmit();
    emit ExecutionStateChanged(
      messages[2].sequenceNumber,
      messages[2].messageId,
      Internal.MessageExecutionState.SUCCESS,
      ""
    );

    Internal.ExecutionReport memory execReport = _generateReportFromMessages(messages);

    uint256 preGhoTokenBalanceUser = dstGhoToken.balanceOf(USER);
    (uint256 preCapacity, uint256 preLevel) = GhoToken(address(dstGhoToken)).getFacilitatorBucket(
      address(dstGhoTokenPool)
    );

    vm.resumeGasMetering();
    s_offRamp.execute(execReport, new uint256[](0));
    vm.pauseGasMetering();

    assertEq(preGhoTokenBalanceUser + 6000 * 1e18, dstGhoToken.balanceOf(USER), "Wrong balance on destination");
    // Facilitator checks
    (uint256 postCapacity, uint256 postLevel) = GhoToken(address(dstGhoToken)).getFacilitatorBucket(
      address(dstGhoTokenPool)
    );
    assertEq(postCapacity, preCapacity);
    assertEq(preLevel + 6000 * 1e18, postLevel, "wrong facilitator bucket level");
  }

  function testRevertRateLimitReached() public {
    // increase bridge limit to hit the rate limit error
    vm.startPrank(AAVE_DAO);
    srcGhoTokenPool.setBridgeLimit(type(uint256).max);
    vm.startPrank(OWNER);

    RateLimiter.Config memory rateLimiterConfig = getOutboundRateLimiterConfig();

    // will revert due to rate limit of tokenPool
    sendRequestGho(1, rateLimiterConfig.capacity + 1, true, false);

    // max capacity, won't revert
    sendRequestGho(1, rateLimiterConfig.capacity, false, false);

    // revert due to capacity exceed
    sendRequestGho(2, 100, true, false);

    // increase blocktime to refill capacity
    vm.warp(BLOCK_TIME + 1);

    // won't revert due to refill
    sendRequestGho(2, 100, false, false);
  }

  function testRevertOnLessTokenToCoverFee() public {
    sendRequestGho(1, 1000, false, true);
  }

  function testRevertBridgeLimitReached() public {
    // increase ccip rate limit to hit the bridge limit error
    vm.startPrank(AAVE_DAO);
    srcGhoTokenPool.setChainRateLimiterConfig(
      DEST_CHAIN_SELECTOR,
      RateLimiter.Config({isEnabled: true, capacity: uint128(INITIAL_BRIDGE_LIMIT * 2), rate: 1e15}),
      getInboundRateLimiterConfig()
    );
    vm.warp(block.timestamp + 100); // wait to refill capacity
    vm.startPrank(OWNER);

    // will revert due to bridge limit
    sendRequestGho(1, uint128(INITIAL_BRIDGE_LIMIT + 1), true, false);

    // max bridge limit, won't revert
    sendRequestGho(1, uint128(INITIAL_BRIDGE_LIMIT), false, false);
    assertEq(srcGhoTokenPool.getCurrentBridgedAmount(), INITIAL_BRIDGE_LIMIT);

    // revert due to bridge limit exceed
    sendRequestGho(2, 1, true, false);

    // increase bridge limit
    vm.startPrank(AAVE_DAO);
    srcGhoTokenPool.setBridgeLimit(INITIAL_BRIDGE_LIMIT + 1);
    vm.startPrank(OWNER);

    // won't revert due to refill
    sendRequestGho(2, 1, false, false);
    assertEq(srcGhoTokenPool.getCurrentBridgedAmount(), INITIAL_BRIDGE_LIMIT + 1);
  }

  function sendRequestGho(
    uint64 expectedSeqNum,
    uint256 amount,
    bool expectRevert,
    bool sendLessFee
  ) public returns (Internal.EVM2EVMMessage memory) {
    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(address(srcGhoToken), amount);
    uint256 expectedFee = s_sourceRouter.getFee(DEST_CHAIN_SELECTOR, message);

    // err mgmt
    uint256 feeToSend = sendLessFee ? expectedFee - 1 : expectedFee;
    expectRevert = sendLessFee ? true : expectRevert;

    IERC20(s_sourceTokens[0]).approve(address(s_sourceRouter), feeToSend); // fee
    IERC20(srcGhoToken).approve(address(s_sourceRouter), amount); // amount

    message.receiver = abi.encode(USER);
    Internal.EVM2EVMMessage memory geEvent = _messageToEvent(
      message,
      expectedSeqNum,
      expectedSeqNum,
      expectedFee,
      OWNER
    );

    if (!expectRevert) {
      vm.expectEmit();
      emit CCIPSendRequested(geEvent);
    } else {
      vm.expectRevert();
    }
    vm.resumeGasMetering();
    s_sourceRouter.ccipSend(DEST_CHAIN_SELECTOR, message);
    vm.pauseGasMetering();

    return geEvent;
  }
}
