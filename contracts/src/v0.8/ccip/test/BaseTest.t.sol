// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableLockReleaseTokenPool} from "../pools/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../pools/UpgradeableBurnMintTokenPool.sol";

import {Test, stdError} from "forge-std/Test.sol";
import {MockARM} from "./mocks/MockARM.sol";
import {StructFactory} from "./StructFactory.sol";

contract BaseTest is Test, StructFactory {
  bool private s_baseTestInitialized;

  MockARM internal s_mockARM;

  address internal PROXY_ADMIN = makeAddr("PROXY_ADMIN");
  uint256 internal BRIDGE_LIMIT = type(uint128).max;

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
    address proxyAdmin,
    address[] memory allowlist
  ) internal returns (address) {
    // Deploy BurnMintTokenPool for GHO token on source chain
    UpgradeableBurnMintTokenPool tokenPoolImpl = new UpgradeableBurnMintTokenPool(ghoToken, arm, allowlist.length > 0);
    // Imple init
    tokenPoolImpl.initialize(owner, allowlist, router);
    // proxy deploy and init
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address)",
      owner,
      allowlist,
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
    address proxyAdmin,
    address[] memory allowlist,
    bool acceptLiquidity
  ) internal returns (address) {
    UpgradeableLockReleaseTokenPool tokenPoolImpl = new UpgradeableLockReleaseTokenPool(
      ghoToken,
      arm,
      allowlist.length > 0,
      acceptLiquidity
    );
    // Imple init
    tokenPoolImpl.initialize(owner, allowlist, router, bridgeLimit);
    // proxy deploy and init
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address,uint256)",
      owner,
      allowlist,
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

  function _writeCurrentBridgedAmount(address pool, uint256 newCurrentBridgedAmount) internal {
    bytes32 CURRENT_BRIDGED_AMOUNT_SLOT = bytes32(uint256(64));
    vm.store(pool, CURRENT_BRIDGED_AMOUNT_SLOT, bytes32(newCurrentBridgedAmount));
  }
}
