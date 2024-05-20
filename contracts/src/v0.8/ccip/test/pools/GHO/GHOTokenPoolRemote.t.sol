// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {MockUpgradeable} from "../../mocks/MockUpgradeable.sol";
import {UpgradeableTokenPool} from "../../../pools/UpgradeableTokenPool.sol";
import {EVM2EVMOnRamp} from "../../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../../offRamp/EVM2EVMOffRamp.sol";
import {BurnMintTokenPool} from "../../../pools/BurnMintTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/UpgradeableBurnMintTokenPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
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
    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.ChainNotAllowed.selector, wrongChainSelector));
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
    vm.expectRevert(abi.encodeWithSelector(UpgradeableTokenPool.ChainNotAllowed.selector, wrongChainSelector));
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

contract GHOTokenPoolEthereum_upgradeability is GHOTokenPoolRemoteSetup {
  function testInitialization() public {
    // Upgradeability
    assertEq(s_pool.REVISION(), 1);
    vm.startPrank(PROXY_ADMIN);
    (bool ok, bytes memory result) = address(s_pool).staticcall(
      abi.encodeWithSelector(TransparentUpgradeableProxy.admin.selector)
    );
    assertTrue(ok, "proxy admin fetch failed");
    address decodedProxyAdmin = abi.decode(result, (address));
    assertEq(decodedProxyAdmin, PROXY_ADMIN, "proxy admin is wrong");
    assertEq(decodedProxyAdmin, _getProxyAdminAddress(address(s_pool)), "proxy admin is wrong");

    // TokenPool
    vm.startPrank(OWNER);
    assertEq(s_pool.getAllowList().length, 0);
    assertEq(s_pool.getAllowListEnabled(), false);
    assertEq(s_pool.getArmProxy(), address(s_mockARM));
    assertEq(s_pool.getRouter(), address(s_sourceRouter));
    assertEq(address(s_pool.getToken()), address(s_burnMintERC677));
    assertEq(s_pool.owner(), AAVE_DAO, "owner is wrong");
  }

  function testUpgrade() public {
    MockUpgradeable newImpl = new MockUpgradeable();
    bytes memory mockImpleParams = abi.encodeWithSignature("initialize()");
    vm.startPrank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeToAndCall(address(newImpl), mockImpleParams);

    vm.startPrank(OWNER);
    assertEq(s_pool.REVISION(), 2);
  }

  function testUpgradeAdminReverts() public {
    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeToAndCall(address(0), bytes(""));
    assertEq(s_pool.REVISION(), 1);

    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeTo(address(0));
    assertEq(s_pool.REVISION(), 1);
  }

  function testChangeAdmin() public {
    assertEq(_getProxyAdminAddress(address(s_pool)), PROXY_ADMIN);

    address newAdmin = makeAddr("newAdmin");
    vm.startPrank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_pool))).changeAdmin(newAdmin);

    assertEq(_getProxyAdminAddress(address(s_pool)), newAdmin, "Admin change failed");
  }

  function testChangeAdminAdminReverts() public {
    assertEq(_getProxyAdminAddress(address(s_pool)), PROXY_ADMIN);

    address newAdmin = makeAddr("newAdmin");
    vm.expectRevert();
    TransparentUpgradeableProxy(payable(address(s_pool))).changeAdmin(newAdmin);

    assertEq(_getProxyAdminAddress(address(s_pool)), PROXY_ADMIN, "Unauthorized admin change");
  }
}
