// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ForkBase} from "./ForkBase.t.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol";
import {Client} from "../../../../../libraries/Client.sol";

contract ForkTokenPoolsUpgrade is ForkBase {
  function setUp() public override {
    super.setUp();

    _upgradeExistingLockReleaseTokenPool();
    _upgradeExistingBurnMintTokenPool();
  }

  function test_upgrade() public {
    vm.selectFork(l1.forkId);

    uint256 amount = 10e18;
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: new bytes(0),
      tokenAmounts: new Client.EVMTokenAmount[](1),
      feeToken: address(0), // will be paying in native tokens for tests
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
    });
    message.tokenAmounts[0].token = address(l1.token);
    message.tokenAmounts[0].amount = amount;

    uint256 feeTokenAmount = l1.router.getFee(l2.chainSelector, message);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, l1.proxyPool));
    l1.router.ccipSend{value: feeTokenAmount}(l2.chainSelector, message);
  }

  function _upgradeExistingLockReleaseTokenPool() internal {
    vm.selectFork(l1.forkId);
    UpgradeableLockReleaseTokenPool poolImpl = new UpgradeableLockReleaseTokenPool(
      address(l1.token),
      l1.tokenPool.getArmProxy(),
      l1.tokenPool.getAllowListEnabled(),
      l1.tokenPool.canAcceptLiquidity()
    );
    _upgradeProxy(TransparentUpgradeableProxy(payable(address(l1.tokenPool))), address(poolImpl));
  }

  function _upgradeExistingBurnMintTokenPool() internal {
    vm.selectFork(l2.forkId);
    UpgradeableBurnMintTokenPool poolImpl = new UpgradeableBurnMintTokenPool(
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
