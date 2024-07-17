// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {MockUpgradeable} from "../../mocks/MockUpgradeable.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {EVM2EVMOnRamp} from "../../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../../offRamp/EVM2EVMOffRamp.sol";
import {BurnMintTokenPool} from "../../../pools/BurnMintTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {GhoTokenPoolRemoteSetupOld} from "./GhoTokenPoolRemoteSetupOld.t.sol";

contract GhoTokenPoolRemoteOld_setRateLimitAdmin is GhoTokenPoolRemoteSetupOld {
  /*function testSetRateLimitAdminSuccess() public {
    assertEq(address(0), s_pool.getRateLimitAdmin());
    changePrank(AAVE_DAO);
    s_pool.setRateLimitAdmin(OWNER);
    assertEq(OWNER, s_pool.getRateLimitAdmin());
  }*/

  // Reverts

  // Should fail because old implementation does not have rate limiter
  function testSetRateLimitRevert() public {
    changePrank(AAVE_DAO);
    vm.expectRevert();
    s_pool.setRateLimitAdmin(OWNER);
  }

  function testSetRateLimitAfterUpgrade() public {
    _upgradeUpgradeableBurnMintTokenPool(payable(address(s_pool)), address(s_burnMintERC677), ARM_PROXY, PROXY_ADMIN);
    changePrank(AAVE_DAO);
    s_pool.setRateLimitAdmin(OWNER);
    assertEq(OWNER, s_pool.getRateLimitAdmin());
  }

  /*
  function testSetRateLimitAdminReverts() public {
    vm.startPrank(STRANGER);

    vm.expectRevert("Only callable by owner");
    s_pool.setRateLimitAdmin(STRANGER);
  }
  */
}
