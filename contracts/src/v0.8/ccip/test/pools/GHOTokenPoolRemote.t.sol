// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {TokenPool} from "../../pools/TokenPool.sol";
import {EVM2EVMOnRamp} from "../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../offRamp/EVM2EVMOffRamp.sol";
import {BurnMintERC677} from "../../../shared/token/ERC677/BurnMintERC677.sol";
import {BurnMintTokenPool} from "../../pools/BurnMintTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {RateLimiter} from "../../libraries/RateLimiter.sol";
import {GHOTokenPoolRemoteSetup} from "./GHOTokenPoolRemoteSetup.t.sol";

contract GHOTokenPoolRemote_lockOrBurn is GHOTokenPoolRemoteSetup {
  function testSetupSuccess() public {
    assertEq(address(s_burnMintERC677), address(s_pool.getToken()));
    assertEq(address(s_mockARM), s_pool.getArmProxy());
    assertEq(false, s_pool.getAllowListEnabled());
    assertEq("BurnMintTokenPool 1.4.0", s_pool.typeAndVersion());
  }

  function testPoolBurnSuccess() public {
    uint256 burnAmount = 20_000e18;
    // inflate facilitator level
    _inflateFacilitatorLevel(address(s_pool), address(s_burnMintERC677), burnAmount);

    deal(address(s_burnMintERC677), address(s_pool), burnAmount);
    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), burnAmount);

    vm.startPrank(s_burnMintOnRamp);

    vm.expectEmit();
    emit TokensConsumed(burnAmount);

    vm.expectEmit();
    emit Transfer(address(s_pool), address(0), burnAmount);

    vm.expectEmit();
    emit Burned(address(s_burnMintOnRamp), burnAmount);

    bytes4 expectedSignature = bytes4(keccak256("burn(uint256)"));
    vm.expectCall(address(s_burnMintERC677), abi.encodeWithSelector(expectedSignature, burnAmount));

    (uint256 preCapacity, uint256 preLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(address(s_pool));

    s_pool.lockOrBurn(OWNER, bytes(""), burnAmount, DEST_CHAIN_SELECTOR, bytes(""));

    // Facilitator checks
    (uint256 postCapacity, uint256 postLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(
      address(s_pool)
    );
    assertEq(postCapacity, preCapacity);
    assertEq(preLevel - burnAmount, postLevel, "wrong facilitator bucket level");

    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), 0);
  }

  // Should not burn tokens if cursed.
  function testPoolBurnRevertNotHealthyReverts() public {
    s_mockARM.voteToCurse(bytes32(0));
    uint256 before = s_burnMintERC677.balanceOf(address(s_pool));
    vm.startPrank(s_burnMintOnRamp);

    vm.expectRevert(EVM2EVMOnRamp.BadARMSignal.selector);
    s_pool.lockOrBurn(OWNER, bytes(""), 1e5, DEST_CHAIN_SELECTOR, bytes(""));

    assertEq(s_burnMintERC677.balanceOf(address(s_pool)), before);
  }

  function testChainNotAllowedReverts() public {
    uint64 wrongChainSelector = 8838833;
    vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, wrongChainSelector));
    s_pool.lockOrBurn(OWNER, bytes(""), 1, wrongChainSelector, bytes(""));
  }

  function testPoolBurnNoPrivilegesReverts() public {
    // Remove privileges
    vm.startPrank(AAVE_DAO);
    GhoToken(address(s_burnMintERC677)).removeFacilitator(address(s_pool));
    vm.stopPrank();

    uint256 amount = 1;
    vm.startPrank(s_burnMintOnRamp);
    vm.expectRevert(stdError.arithmeticError);
    s_pool.lockOrBurn(STRANGER, bytes(""), amount, DEST_CHAIN_SELECTOR, bytes(""));
  }

  function testBucketLevelNotEnoughReverts() public {
    (, uint256 bucketLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(address(s_pool));
    assertEq(bucketLevel, 0);

    uint256 amount = 1;
    vm.expectCall(address(s_burnMintERC677), abi.encodeWithSelector(GhoToken.burn.selector, amount));
    vm.expectRevert(stdError.arithmeticError);
    vm.startPrank(s_burnMintOnRamp);
    s_pool.lockOrBurn(STRANGER, bytes(""), amount, DEST_CHAIN_SELECTOR, bytes(""));
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = getOutboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_burnMintERC677))
    );
    vm.startPrank(s_burnMintOnRamp);
    s_pool.lockOrBurn(STRANGER, bytes(""), amount, DEST_CHAIN_SELECTOR, bytes(""));
  }
}

contract GHOTokenPoolRemote_releaseOrMint is GHOTokenPoolRemoteSetup {
  function testPoolMintSuccess() public {
    uint256 amount = 1e19;
    vm.startPrank(s_burnMintOffRamp);
    vm.expectEmit();
    emit Transfer(address(0), OWNER, amount);
    s_pool.releaseOrMint(bytes(""), OWNER, amount, DEST_CHAIN_SELECTOR, bytes(""));
    assertEq(s_burnMintERC677.balanceOf(OWNER), amount);
  }

  function testPoolMintNotHealthyReverts() public {
    // Should not mint tokens if cursed.
    s_mockARM.voteToCurse(bytes32(0));
    uint256 before = s_burnMintERC677.balanceOf(OWNER);
    vm.startPrank(s_burnMintOffRamp);
    vm.expectRevert(EVM2EVMOffRamp.BadARMSignal.selector);
    s_pool.releaseOrMint(bytes(""), OWNER, 1e5, DEST_CHAIN_SELECTOR, bytes(""));
    assertEq(s_burnMintERC677.balanceOf(OWNER), before);
  }

  function testChainNotAllowedReverts() public {
    uint64 wrongChainSelector = 8838833;
    vm.expectRevert(abi.encodeWithSelector(TokenPool.ChainNotAllowed.selector, wrongChainSelector));
    s_pool.releaseOrMint(bytes(""), STRANGER, 1, wrongChainSelector, bytes(""));
  }

  function testPoolMintNoPrivilegesReverts() public {
    // Remove privileges
    vm.startPrank(AAVE_DAO);
    GhoToken(address(s_burnMintERC677)).removeFacilitator(address(s_pool));
    vm.stopPrank();

    uint256 amount = 1;
    vm.startPrank(s_burnMintOffRamp);
    vm.expectRevert("FACILITATOR_BUCKET_CAPACITY_EXCEEDED");
    s_pool.releaseOrMint(bytes(""), STRANGER, amount, DEST_CHAIN_SELECTOR, bytes(""));
  }

  function testBucketCapacityExceededReverts() public {
    // Mint all the bucket capacity
    (uint256 bucketCapacity, ) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(address(s_pool));
    _inflateFacilitatorLevel(address(s_pool), address(s_burnMintERC677), bucketCapacity);
    (uint256 currCapacity, uint256 currLevel) = GhoToken(address(s_burnMintERC677)).getFacilitatorBucket(
      address(s_pool)
    );
    assertEq(currCapacity, currLevel);

    uint256 amount = 1;
    vm.expectCall(address(s_burnMintERC677), abi.encodeWithSelector(GhoToken.mint.selector, STRANGER, amount));
    vm.expectRevert("FACILITATOR_BUCKET_CAPACITY_EXCEEDED");
    vm.startPrank(s_burnMintOffRamp);
    s_pool.releaseOrMint(bytes(""), STRANGER, amount, DEST_CHAIN_SELECTOR, bytes(""));
  }

  function testTokenMaxCapacityExceededReverts() public {
    RateLimiter.Config memory rateLimiterConfig = getInboundRateLimiterConfig();
    uint256 capacity = rateLimiterConfig.capacity;
    uint256 amount = 10 * capacity;

    vm.expectRevert(
      abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, capacity, amount, address(s_burnMintERC677))
    );
    vm.startPrank(s_burnMintOffRamp);
    s_pool.releaseOrMint(bytes(""), STRANGER, amount, DEST_CHAIN_SELECTOR, bytes(""));
  }
}
