// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.t.sol";
import {IPool} from "../../../interfaces/pools/IPool.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableTokenPool} from "../../../pools/GHO/UpgradeableTokenPool.sol";
import {EVM2EVMOnRamp} from "../../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../../offRamp/EVM2EVMOffRamp.sol";
import {RateLimiter} from "../../../libraries/RateLimiter.sol";
import {BurnMintERC677} from "../../../../shared/token/ERC677/BurnMintERC677.sol";
import {Router} from "../../../Router.sol";
import {IERC165} from "../../../../vendor/openzeppelin-solidity/v4.8.3/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "../../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RouterSetup} from "../../router/RouterSetup.t.sol";
import {BaseTest} from "../../BaseTest.t.sol";
import {GhoBaseTest} from "./GhoBaseTest.t.sol";

contract GhoTokenPoolEthereumSetup is RouterSetup, GhoBaseTest {
  IERC20 internal s_token;
  UpgradeableLockReleaseTokenPool internal s_ghoTokenPool;

  address internal s_allowedOnRamp = address(123);
  address internal s_allowedOffRamp = address(234);

  function setUp() public virtual override(RouterSetup, BaseTest) {
    RouterSetup.setUp();

    // GHO deployment
    GhoToken ghoToken = new GhoToken(AAVE_DAO);
    s_token = IERC20(address(ghoToken));
    deal(address(s_token), OWNER, type(uint128).max);

    // Set up UpgradeableTokenPool with permission to mint/burn
    s_ghoTokenPool = UpgradeableLockReleaseTokenPool(
      _deployUpgradeableLockReleaseTokenPool(
        address(s_token),
        address(s_mockARM),
        address(s_sourceRouter),
        AAVE_DAO,
        INITIAL_BRIDGE_LIMIT,
        PROXY_ADMIN
      )
    );

    UpgradeableTokenPool.ChainUpdate[] memory chainUpdate = new UpgradeableTokenPool.ChainUpdate[](1);
    chainUpdate[0] = UpgradeableTokenPool.ChainUpdate({
      remoteChainSelector: DEST_CHAIN_SELECTOR,
      allowed: true,
      outboundRateLimiterConfig: getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: getInboundRateLimiterConfig()
    });

    changePrank(AAVE_DAO);
    s_ghoTokenPool.applyChainUpdates(chainUpdate);
    s_ghoTokenPool.setRebalancer(OWNER);
    changePrank(OWNER);

    Router.OnRamp[] memory onRampUpdates = new Router.OnRamp[](1);
    Router.OffRamp[] memory offRampUpdates = new Router.OffRamp[](1);
    onRampUpdates[0] = Router.OnRamp({destChainSelector: DEST_CHAIN_SELECTOR, onRamp: s_allowedOnRamp});
    offRampUpdates[0] = Router.OffRamp({sourceChainSelector: SOURCE_CHAIN_SELECTOR, offRamp: s_allowedOffRamp});
    s_sourceRouter.applyRampUpdates(onRampUpdates, new Router.OffRamp[](0), offRampUpdates);
  }
}
