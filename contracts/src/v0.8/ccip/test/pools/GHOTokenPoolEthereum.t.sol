// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {IPool} from "../../interfaces/pools/IPool.sol";
import {LockReleaseTokenPool} from "../../pools/LockReleaseTokenPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {TokenPool} from "../../pools/TokenPool.sol";
import {EVM2EVMOnRamp} from "../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../offRamp/EVM2EVMOffRamp.sol";
import {RateLimiter} from "../../libraries/RateLimiter.sol";
import {BurnMintERC677} from "../../../shared/token/ERC677/BurnMintERC677.sol";
import {Router} from "../../Router.sol";
import {IERC165} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {GHOTokenPoolEthereumSetup} from "./GHOTokenPoolEthereumSetup.t.sol";

contract GHOTokenPoolEthereum_setRebalancer is GHOTokenPoolEthereumSetup {
  function testSetRebalancerSuccess() public {
    assertEq(address(s_ghoTokenPool.getRebalancer()), OWNER);
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setRebalancer(STRANGER);
    assertEq(address(s_ghoTokenPool.getRebalancer()), STRANGER);
  }

  function testSetRebalancerReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert("Only callable by owner");
    s_ghoTokenPool.setRebalancer(STRANGER);
  }
}

contract GHOTokenPoolEthereum_lockOrBurn is GHOTokenPoolEthereumSetup {
  error SenderNotAllowed(address sender);

  event Locked(address indexed sender, uint256 amount);
  event TokensConsumed(uint256 tokens);

  function testFuzz_LockOrBurnNoAllowListSuccess(uint256 amount) public {
    amount = bound(amount, 1, getOutboundRateLimiterConfig().capacity);
    changePrank(s_allowedOnRamp);

    vm.expectEmit();
    emit TokensConsumed(amount);
    vm.expectEmit();
    emit Locked(s_allowedOnRamp, amount);

    s_ghoTokenPool.lockOrBurn(STRANGER, bytes(""), amount, DEST_CHAIN_SELECTOR, bytes(""));
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = getOutboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_token))
    );
    vm.startPrank(s_allowedOnRamp);
    s_ghoTokenPool.lockOrBurn(STRANGER, bytes(""), amount, DEST_CHAIN_SELECTOR, bytes(""));
  }
}

contract GHOTokenPoolEthereum_releaseOrMint is GHOTokenPoolEthereumSetup {
  event TokensConsumed(uint256 tokens);
  event Released(address indexed sender, address indexed recipient, uint256 amount);

  function setUp() public virtual override {
    GHOTokenPoolEthereumSetup.setUp();
    TokenPool.ChainUpdate[] memory chainUpdate = new TokenPool.ChainUpdate[](1);
    chainUpdate[0] = TokenPool.ChainUpdate({
      remoteChainSelector: SOURCE_CHAIN_SELECTOR,
      allowed: true,
      outboundRateLimiterConfig: getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: getInboundRateLimiterConfig()
    });

    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(chainUpdate);
  }

  function test_ReleaseOrMintSuccess() public {
    vm.startPrank(s_allowedOffRamp);

    uint256 amount = 100;
    deal(address(s_token), address(s_ghoTokenPool), amount);

    vm.expectEmit();
    emit TokensConsumed(amount);
    vm.expectEmit();
    emit Released(s_allowedOffRamp, OWNER, amount);

    s_ghoTokenPool.releaseOrMint(bytes(""), OWNER, amount, SOURCE_CHAIN_SELECTOR, bytes(""));
  }

  function testFuzz_ReleaseOrMintSuccess(address recipient, uint256 amount) public {
    // Since the owner already has tokens this would break the checks
    vm.assume(recipient != OWNER);
    vm.assume(recipient != address(0));
    vm.assume(recipient != address(s_token));

    // Makes sure the pool always has enough funds
    deal(address(s_token), address(s_ghoTokenPool), amount);
    vm.startPrank(s_allowedOffRamp);

    uint256 capacity = getInboundRateLimiterConfig().capacity;
    // Determine if we hit the rate limit or the txs should succeed.
    if (amount > capacity) {
      vm.expectRevert(
        abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_token))
      );
    } else {
      // Only rate limit if the amount is >0
      if (amount > 0) {
        vm.expectEmit();
        emit TokensConsumed(amount);
      }

      vm.expectEmit();
      emit Released(s_allowedOffRamp, recipient, amount);
    }

    s_ghoTokenPool.releaseOrMint(bytes(""), recipient, amount, SOURCE_CHAIN_SELECTOR, bytes(""));
  }

  function testChainNotAllowedReverts() public {
    TokenPool.ChainUpdate[] memory chainUpdate = new TokenPool.ChainUpdate[](1);
    chainUpdate[0] = TokenPool.ChainUpdate({
      remoteChainSelector: SOURCE_CHAIN_SELECTOR,
      allowed: false,
      outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
      inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
    });

    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(chainUpdate);
    vm.stopPrank();

    vm.startPrank(s_allowedOffRamp);

    vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, SOURCE_CHAIN_SELECTOR));
    s_ghoTokenPool.releaseOrMint(bytes(""), OWNER, 1e5, SOURCE_CHAIN_SELECTOR, bytes(""));
  }

  function testPoolMintNotHealthyReverts() public {
    // Should not mint tokens if cursed.
    s_mockARM.voteToCurse(bytes32(0));
    uint256 before = s_token.balanceOf(OWNER);
    vm.startPrank(s_allowedOffRamp);
    vm.expectRevert(EVM2EVMOffRamp.BadARMSignal.selector);
    s_ghoTokenPool.releaseOrMint(bytes(""), OWNER, 1e5, SOURCE_CHAIN_SELECTOR, bytes(""));
    assertEq(s_token.balanceOf(OWNER), before);
  }

  function testReleaseNoFundsReverts() public {
    uint256 amount = 1;
    vm.expectRevert(stdError.arithmeticError);
    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(bytes(""), STRANGER, amount, SOURCE_CHAIN_SELECTOR, bytes(""));
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = getInboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_token))
    );
    vm.startPrank(s_allowedOffRamp);
    s_ghoTokenPool.releaseOrMint(bytes(""), STRANGER, amount, SOURCE_CHAIN_SELECTOR, bytes(""));
  }
}

contract GHOTokenPoolEthereum_canAcceptLiquidity is GHOTokenPoolEthereumSetup {
  function test_CanAcceptLiquiditySuccess() public {
    assertEq(true, s_ghoTokenPool.canAcceptLiquidity());

    s_ghoTokenPool = new UpgradeableLockReleaseTokenPool(
      address(s_token),
      address(s_mockARM),
      false,
      address(s_sourceRouter)
    );

    assertEq(false, s_ghoTokenPool.canAcceptLiquidity());
  }
}

contract GHOTokenPoolEthereum_provideLiquidity is GHOTokenPoolEthereumSetup {
  function testFuzz_ProvideLiquiditySuccess(uint256 amount) public {
    vm.assume(amount < type(uint128).max);

    uint256 balancePre = s_token.balanceOf(OWNER);
    s_token.approve(address(s_ghoTokenPool), amount);

    s_ghoTokenPool.provideLiquidity(amount);

    assertEq(s_token.balanceOf(OWNER), balancePre - amount);
    assertEq(s_token.balanceOf(address(s_ghoTokenPool)), amount);
  }

  // Reverts

  function test_UnauthorizedReverts() public {
    vm.startPrank(STRANGER);
    vm.expectRevert(abi.encodeWithSelector(LockReleaseTokenPool.Unauthorized.selector, STRANGER));

    s_ghoTokenPool.provideLiquidity(1);
  }

  function testFuzz_ExceedsAllowance(uint256 amount) public {
    vm.assume(amount > 0);
    vm.expectRevert(stdError.arithmeticError);
    s_ghoTokenPool.provideLiquidity(amount);
  }

  function testLiquidityNotAcceptedReverts() public {
    s_ghoTokenPool = new UpgradeableLockReleaseTokenPool(
      address(s_token),
      address(s_mockARM),
      false,
      address(s_sourceRouter)
    );

    vm.expectRevert(LockReleaseTokenPool.LiquidityNotAccepted.selector);
    s_ghoTokenPool.provideLiquidity(1);
  }
}

contract GHOTokenPoolEthereum_withdrawalLiquidity is GHOTokenPoolEthereumSetup {
  function testFuzz_WithdrawalLiquiditySuccess(uint256 amount) public {
    vm.assume(amount < type(uint128).max);

    uint256 balancePre = s_token.balanceOf(OWNER);
    s_token.approve(address(s_ghoTokenPool), amount);
    s_ghoTokenPool.provideLiquidity(amount);

    s_ghoTokenPool.withdrawLiquidity(amount);

    assertEq(s_token.balanceOf(OWNER), balancePre);
  }

  // Reverts

  function test_UnauthorizedReverts() public {
    vm.startPrank(STRANGER);
    vm.expectRevert(abi.encodeWithSelector(LockReleaseTokenPool.Unauthorized.selector, STRANGER));

    s_ghoTokenPool.withdrawLiquidity(1);
  }

  function testInsufficientLiquidityReverts() public {
    uint256 maxUint128 = 2 ** 128 - 1;
    s_token.approve(address(s_ghoTokenPool), maxUint128);
    s_ghoTokenPool.provideLiquidity(maxUint128);

    changePrank(address(s_ghoTokenPool));
    s_token.transfer(OWNER, maxUint128);
    changePrank(OWNER);

    vm.expectRevert(LockReleaseTokenPool.InsufficientLiquidity.selector);
    s_ghoTokenPool.withdrawLiquidity(1);
  }
}

contract GHOTokenPoolEthereum_supportsInterface is GHOTokenPoolEthereumSetup {
  function testSupportsInterfaceSuccess() public {
    assertTrue(s_ghoTokenPool.supportsInterface(s_ghoTokenPool.getLockReleaseInterfaceId()));
    assertTrue(s_ghoTokenPool.supportsInterface(type(IPool).interfaceId));
    assertTrue(s_ghoTokenPool.supportsInterface(type(IERC165).interfaceId));
  }
}

contract GHOTokenPoolEthereum_setChainRateLimiterConfig is GHOTokenPoolEthereumSetup {
  event ConfigChanged(RateLimiter.Config);
  event ChainConfigured(
    uint64 chainSelector,
    RateLimiter.Config outboundRateLimiterConfig,
    RateLimiter.Config inboundRateLimiterConfig
  );

  uint64 internal s_remoteChainSelector;

  function setUp() public virtual override {
    GHOTokenPoolEthereumSetup.setUp();
    TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
    s_remoteChainSelector = 123124;
    chainUpdates[0] = TokenPool.ChainUpdate({
      remoteChainSelector: s_remoteChainSelector,
      allowed: true,
      outboundRateLimiterConfig: getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: getInboundRateLimiterConfig()
    });
    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(chainUpdates);
    changePrank(OWNER);
  }

  function testFuzz_SetChainRateLimiterConfigSuccess(uint128 capacity, uint128 rate, uint32 newTime) public {
    // Cap the lower bound to 4 so 4/2 is still >= 2
    vm.assume(capacity >= 4);
    // Cap the lower bound to 2 so 2/2 is still >= 1
    rate = uint128(bound(rate, 2, capacity - 2));
    // Bucket updates only work on increasing time
    newTime = uint32(bound(newTime, block.timestamp + 1, type(uint32).max));
    vm.warp(newTime);

    uint256 oldOutboundTokens = s_ghoTokenPool.getCurrentOutboundRateLimiterState(s_remoteChainSelector).tokens;
    uint256 oldInboundTokens = s_ghoTokenPool.getCurrentInboundRateLimiterState(s_remoteChainSelector).tokens;

    RateLimiter.Config memory newOutboundConfig = RateLimiter.Config({isEnabled: true, capacity: capacity, rate: rate});
    RateLimiter.Config memory newInboundConfig = RateLimiter.Config({
      isEnabled: true,
      capacity: capacity / 2,
      rate: rate / 2
    });

    vm.expectEmit();
    emit ConfigChanged(newOutboundConfig);
    vm.expectEmit();
    emit ConfigChanged(newInboundConfig);
    vm.expectEmit();
    emit ChainConfigured(s_remoteChainSelector, newOutboundConfig, newInboundConfig);

    changePrank(AAVE_DAO);
    s_ghoTokenPool.setChainRateLimiterConfig(s_remoteChainSelector, newOutboundConfig, newInboundConfig);

    uint256 expectedTokens = RateLimiter._min(newOutboundConfig.capacity, oldOutboundTokens);

    RateLimiter.TokenBucket memory bucket = s_ghoTokenPool.getCurrentOutboundRateLimiterState(s_remoteChainSelector);
    assertEq(bucket.capacity, newOutboundConfig.capacity);
    assertEq(bucket.rate, newOutboundConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);

    expectedTokens = RateLimiter._min(newInboundConfig.capacity, oldInboundTokens);

    bucket = s_ghoTokenPool.getCurrentInboundRateLimiterState(s_remoteChainSelector);
    assertEq(bucket.capacity, newInboundConfig.capacity);
    assertEq(bucket.rate, newInboundConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);
  }

  function testOnlyOwnerOrRateLimitAdminReverts() public {
    address rateLimiterAdmin = address(28973509103597907);

    changePrank(AAVE_DAO);
    s_ghoTokenPool.setRateLimitAdmin(rateLimiterAdmin);

    changePrank(rateLimiterAdmin);

    s_ghoTokenPool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      getOutboundRateLimiterConfig(),
      getInboundRateLimiterConfig()
    );

    changePrank(AAVE_DAO);

    s_ghoTokenPool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      getOutboundRateLimiterConfig(),
      getInboundRateLimiterConfig()
    );
  }

  // Reverts

  function testOnlyOwnerReverts() public {
    changePrank(STRANGER);

    vm.expectRevert(abi.encodeWithSelector(LockReleaseTokenPool.Unauthorized.selector, STRANGER));
    s_ghoTokenPool.setChainRateLimiterConfig(
      s_remoteChainSelector,
      getOutboundRateLimiterConfig(),
      getInboundRateLimiterConfig()
    );
  }

  function testNonExistentChainReverts() public {
    uint64 wrongChainSelector = 9084102894;

    vm.expectRevert(abi.encodeWithSelector(TokenPool.NonExistentChain.selector, wrongChainSelector));
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setChainRateLimiterConfig(
      wrongChainSelector,
      getOutboundRateLimiterConfig(),
      getInboundRateLimiterConfig()
    );
  }
}

contract GHOTokenPoolEthereum_setRateLimitAdmin is GHOTokenPoolEthereumSetup {
  function testSetRateLimitAdminSuccess() public {
    assertEq(address(0), s_ghoTokenPool.getRateLimitAdmin());
    changePrank(AAVE_DAO);
    s_ghoTokenPool.setRateLimitAdmin(OWNER);
    assertEq(OWNER, s_ghoTokenPool.getRateLimitAdmin());
  }

  // Reverts

  function testSetRateLimitAdminReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert("Only callable by owner");
    s_ghoTokenPool.setRateLimitAdmin(STRANGER);
  }
}
