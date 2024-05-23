// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test, stdError} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {MockARM} from "./mocks/MockARM.sol";
import {StructFactory} from "./StructFactory.sol";

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableLockReleaseTokenPool} from "../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {IBurnMintERC20} from "../../shared/token/ERC20/IBurnMintERC20.sol";

contract BaseTest is Test, StructFactory {
  bool private s_baseTestInitialized;

  MockARM internal s_mockARM;

  function setUp() public virtual {
    // BaseTest.setUp is often called multiple times from tests' setUp due to inheritance.
    if (s_baseTestInitialized) return;
    s_baseTestInitialized = true;

    // Set the sender to OWNER permanently
    vm.startPrank(OWNER);
    deal(OWNER, 1e20);
    vm.label(OWNER, "Owner");
    vm.label(STRANGER, "Stranger");

    // Set the block time to a constant known value
    vm.warp(BLOCK_TIME);

    s_mockARM = new MockARM();
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

  function _inflateFacilitatorLevel(address tokenPool, address ghoToken, uint256 amount) internal {
    vm.stopPrank();
    vm.prank(tokenPool);
    IBurnMintERC20(ghoToken).mint(address(0), amount);
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
