// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {GhoTokenPoolRemoteSetup} from "./GhoTokenPoolRemoteSetup.t.sol";

contract GhoTokenPoolRemoteUpgrade is GhoTokenPoolRemoteSetup {
  // Unable to call setRateLimitAdmin() before upgrade
  function testSetRateLimitAdminRevertsBeforeUpgrade() public {
    s_pool = UpgradeableBurnMintTokenPool(_deployUpgradeableBurnMintTokenPoolOld(
        address(s_burnMintERC677),
        address(s_mockARM),
        address(s_sourceRouter),
        AAVE_DAO, 
        PROXY_ADMIN
    ));
    vm.prank(AAVE_DAO);
    vm.expectRevert();
    s_pool.setRateLimitAdmin(AAVE_DAO);
  }

  // Able to call setRateLimitAdmin() after upgrade
  function testUpgradeAndSetRateLimitAdmin() public {
    // Assume existing remote pool as is deployed
    s_pool = UpgradeableBurnMintTokenPool(_deployUpgradeableBurnMintTokenPoolOld(
        address(s_burnMintERC677),
        address(s_mockARM),
        address(s_sourceRouter),
        AAVE_DAO, 
        PROXY_ADMIN
    ));
    
    // Deploy new implementation
    UpgradeableBurnMintTokenPool tokenPoolImpl = new UpgradeableBurnMintTokenPool(address(s_burnMintERC677), address(s_mockARM), false);
    // Do the upgrade
    vm.prank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeTo(address(tokenPoolImpl));

    // Set rate limit admin now works
    vm.prank(AAVE_DAO);
    s_pool.setRateLimitAdmin(OWNER);
    assertEq(OWNER, s_pool.getRateLimitAdmin());
  }

  // Unable to call initialize() on proxy after upgrade
  function testInitializeRevertsAfterUpgrade() public {
    s_pool = UpgradeableBurnMintTokenPool(_deployUpgradeableBurnMintTokenPoolOld(
        address(s_burnMintERC677),
        address(s_mockARM),
        address(s_sourceRouter),
        AAVE_DAO, 
        PROXY_ADMIN
    ));

    // Deploy new implementation
    UpgradeableBurnMintTokenPool tokenPoolImpl = new UpgradeableBurnMintTokenPool(address(s_burnMintERC677), address(s_mockARM), false);
    // Do the upgrade
    vm.prank(PROXY_ADMIN);
    TransparentUpgradeableProxy(payable(address(s_pool))).upgradeTo(address(tokenPoolImpl));

    vm.startPrank(OWNER);
    vm.expectRevert("Initializable: contract is already initialized");
    s_pool.initialize(OWNER, new address[](0), address(s_sourceRouter));
  }
}
