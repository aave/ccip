// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol";
import {Client} from "../../../../../libraries/Client.sol";
import {Internal} from "../../../../../libraries/Internal.sol";
import {ForkBase} from "./ForkBase.t.sol";
import {UpgradeableLockReleaseTokenPool_Sepolia} from "./LegacyTestnetTokenPools/UpgradeableLockReleaseTokenPool_Sepolia.sol";
import {UpgradeableBurnMintTokenPool_ArbSepolia} from "./LegacyTestnetTokenPools/UpgradeableBurnMintTokenPool_ArbSepolia.sol";

contract ForkPoolUpgradeAfterMigration is ForkBase {
  function setUp() public override {
    super.setUp();

    // #1: deploy new implementation & upgrade token pools
    vm.selectFork(l1.forkId);
    _upgradeExistingLockReleaseTokenPool();

    vm.selectFork(l2.forkId);
    _upgradeExistingBurnMintTokenPool();

    // #2: setProxyPool
    vm.selectFork(l1.forkId);
    vm.prank(l1.tokenPool.owner());
    l1.tokenPool.setProxyPool(l1.proxyPool);

    vm.selectFork(l2.forkId);
    vm.prank(l2.tokenPool.owner());
    l2.tokenPool.setProxyPool(l2.proxyPool);
  }

  function testLockOrBurnViaRouter() public {
    uint256 amount = 10e18;
    Client.EVM2AnyMessage memory message = _generateMessage(alice, 1);

    {
      vm.selectFork(l1.forkId);

      message.tokenAmounts[0] = Client.EVMTokenAmount({token: address(l1.token), amount: amount});
      uint256 feeTokenAmount = l1.router.getFee(l2.chainSelector, message);

      // router uses 1_5 onRamp
      assertEq(l1.router.getOnRamp(l2.chainSelector), address(l1.EVM2EVMOnRamp1_5));
      vm.expectEmit();
      emit CCIPSendRequested(_messageToEvent(message, l1.EVM2EVMOnRamp1_5, feeTokenAmount, alice, true));
      vm.prank(alice);
      l1.router.ccipSend{value: feeTokenAmount}(l2.chainSelector, message);
    }

    {
      vm.selectFork(l2.forkId);

      message.tokenAmounts[0] = Client.EVMTokenAmount({token: address(l2.token), amount: amount});
      uint256 feeTokenAmount = l2.router.getFee(l1.chainSelector, message);

      // router uses 1_5 onRamp
      assertEq(l2.router.getOnRamp(l1.chainSelector), address(l2.EVM2EVMOnRamp1_5));
      vm.expectEmit();
      emit CCIPSendRequested(_messageToEvent(message, l2.EVM2EVMOnRamp1_5, feeTokenAmount, alice, false));
      vm.prank(alice);
      l2.router.ccipSend{value: feeTokenAmount}(l1.chainSelector, message);
    }
  }

  function testRevertLockOrBurnVia1_2OnRamp() public {
    uint256 amount = 10e18;
    {
      vm.selectFork(l1.forkId);
      vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, address(l1.EVM2EVMOnRamp1_2)));
      vm.prank(address(l1.EVM2EVMOnRamp1_2));
      l1.tokenPool.lockOrBurn(alice, abi.encode(alice), amount, l2.chainSelector, "");
    }
    {
      vm.selectFork(l2.forkId);
      vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, address(l2.EVM2EVMOnRamp1_2)));
      vm.prank(address(l2.EVM2EVMOnRamp1_2));
      l2.tokenPool.lockOrBurn(alice, abi.encode(alice), amount, l1.chainSelector, "");
    }
  }

  function testReleaseOrMintVia1_2OffRamp() public {
    uint256 amount = 10e18;
    {
      vm.selectFork(l1.forkId);
      uint256 balanceBefore = l1.token.balanceOf(alice);
      // mock release on legacy offramp
      vm.prank(address(l1.EVM2EVMOffRamp1_2));
      l1.tokenPool.releaseOrMint(abi.encode(alice), alice, amount, l2.chainSelector, "");
      assertEq(l1.token.balanceOf(alice), balanceBefore + amount);
    }
    {
      vm.selectFork(l2.forkId);
      uint256 balanceBefore = l2.token.balanceOf(alice);
      // mock release on legacy offramp
      vm.prank(address(l2.EVM2EVMOffRamp1_2));
      l2.tokenPool.releaseOrMint(abi.encode(alice), alice, amount, l1.chainSelector, "");
      assertEq(l2.token.balanceOf(alice), balanceBefore + amount);
    }
  }

  function testReleaseOrMintVia1_5OffRamp() public {
    uint256 amount = 10e18;
    {
      vm.selectFork(l1.forkId);
      uint256 balanceBefore = l1.token.balanceOf(alice);
      // mock release on legacy offramp
      vm.prank(address(l1.EVM2EVMOffRamp1_5));
      l1.tokenPool.releaseOrMint(abi.encode(alice), alice, amount, l2.chainSelector, "");
      assertEq(l1.token.balanceOf(alice), balanceBefore + amount);
    }
    {
      vm.selectFork(l2.forkId);
      uint256 balanceBefore = l2.token.balanceOf(alice);
      // mock release on legacy offramp
      vm.prank(address(l2.EVM2EVMOffRamp1_5));
      l2.tokenPool.releaseOrMint(abi.encode(alice), alice, amount, l1.chainSelector, "");
      assertEq(l2.token.balanceOf(alice), balanceBefore + amount);
    }
  }

  function _upgradeExistingLockReleaseTokenPool() internal {
    UpgradeableLockReleaseTokenPool_Sepolia poolImpl = new UpgradeableLockReleaseTokenPool_Sepolia(
      address(l1.token),
      l1.tokenPool.getArmProxy(),
      l1.tokenPool.getAllowListEnabled(),
      l1.tokenPool.canAcceptLiquidity()
    );
    _upgradeProxy(TransparentUpgradeableProxy(payable(address(l1.tokenPool))), address(poolImpl));
  }

  function _upgradeExistingBurnMintTokenPool() internal {
    UpgradeableBurnMintTokenPool_ArbSepolia poolImpl = new UpgradeableBurnMintTokenPool_ArbSepolia(
      address(l2.token),
      l2.tokenPool.getArmProxy(),
      l2.tokenPool.getAllowListEnabled()
    );
    _upgradeProxy(TransparentUpgradeableProxy(payable(address(l2.tokenPool))), address(poolImpl));
  }

  function _upgradeProxy(TransparentUpgradeableProxy proxy, address impl) private {
    address proxyAdminAddress = address(
      uint160(uint256(vm.load(address(proxy), bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1))))
    );
    assertNotEq(proxyAdminAddress, address(0), "version mismatch: proxyAdmin");
    if (proxyAdminAddress.code.length != 0) {
      ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
      assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));
      vm.prank(proxyAdmin.owner());
      proxyAdmin.upgrade(proxy, address(impl));
    } else {
      // sepolia has proxy admin as an eoa
      vm.prank(proxyAdminAddress);
      proxy.upgradeTo(address(impl));
    }
  }
}
