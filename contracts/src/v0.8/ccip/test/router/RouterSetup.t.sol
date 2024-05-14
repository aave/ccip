// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableLockReleaseTokenPool} from "../../pools/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../pools/UpgradeableBurnMintTokenPool.sol";

import {BaseTest} from "../BaseTest.t.sol";
import {Router} from "../../Router.sol";
import {WETH9} from "../WETH9.sol";
import {Client} from "../../libraries/Client.sol";

contract RouterSetup is BaseTest {
  Router internal s_sourceRouter;
  Router internal s_destRouter;

  function setUp() public virtual override {
    BaseTest.setUp();

    if (address(s_sourceRouter) == address(0)) {
      WETH9 weth = new WETH9();
      s_sourceRouter = new Router(address(weth), address(s_mockARM));
      vm.label(address(s_sourceRouter), "sourceRouter");
    }
    if (address(s_destRouter) == address(0)) {
      WETH9 weth = new WETH9();
      s_destRouter = new Router(address(weth), address(s_mockARM));
      vm.label(address(s_destRouter), "destRouter");
    }
  }

  function generateReceiverMessage(uint64 chainSelector) internal pure returns (Client.Any2EVMMessage memory) {
    Client.EVMTokenAmount[] memory ta = new Client.EVMTokenAmount[](0);
    return
      Client.Any2EVMMessage({
        messageId: bytes32("a"),
        sourceChainSelector: chainSelector,
        sender: bytes("a"),
        data: bytes("a"),
        destTokenAmounts: ta
      });
  }

  function _deployUpgradeableBurnMintTokenPool(
    address ghoToken,
    address arm,
    address router,
    address owner,
    address proxyAdmin
  ) internal returns (address) {
    // Deploy BurnMintTokenPool for GHO token on source chain
    UpgradeableBurnMintTokenPool tokenPoolImpl = new UpgradeableBurnMintTokenPool(ghoToken, arm, false);
    // Imple init
    address[] memory emptyArray = new address[](0);
    tokenPoolImpl.initialize(owner, emptyArray, router);
    // proxy deploy and init
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address)",
      owner,
      emptyArray,
      router
    );
    TransparentUpgradeableProxy tokenPoolProxy = new TransparentUpgradeableProxy(
      address(tokenPoolImpl),
      proxyAdmin,
      tokenPoolInitParams
    );
    // Manage ownership
    vm.stopPrank();
    vm.prank(owner);
    UpgradeableBurnMintTokenPool(address(tokenPoolProxy)).acceptOwnership();
    vm.startPrank(OWNER);

    return address(tokenPoolProxy);
  }

  function _deployUpgradeableLockReleaseTokenPool(
    address ghoToken,
    address arm,
    address router,
    address owner,
    uint256 bridgeLimit,
    address proxyAdmin
  ) internal returns (address) {
    UpgradeableLockReleaseTokenPool tokenPoolImpl = new UpgradeableLockReleaseTokenPool(ghoToken, arm, false, true);
    // Imple init
    address[] memory emptyArray = new address[](0);
    tokenPoolImpl.initialize(owner, emptyArray, router, bridgeLimit);
    // proxy deploy and init
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address,uint256)",
      owner,
      emptyArray,
      router,
      bridgeLimit
    );
    TransparentUpgradeableProxy tokenPoolProxy = new TransparentUpgradeableProxy(
      address(tokenPoolImpl),
      proxyAdmin,
      tokenPoolInitParams
    );

    // Manage ownership
    vm.stopPrank();
    vm.prank(owner);
    UpgradeableLockReleaseTokenPool(address(tokenPoolProxy)).acceptOwnership();
    vm.startPrank(OWNER);

    return address(tokenPoolProxy);
  }

  function _getProxyAdminAddress(address proxy) internal view returns (address) {
    bytes32 ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 adminSlot = vm.load(proxy, ERC1967_ADMIN_SLOT);
    return address(uint160(uint256(adminSlot)));
  }

  function _getProxyImplementationAddress(address proxy) internal view returns (address) {
    bytes32 ERC1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 implSlot = vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT);
    return address(uint160(uint256(implSlot)));
  }
}
