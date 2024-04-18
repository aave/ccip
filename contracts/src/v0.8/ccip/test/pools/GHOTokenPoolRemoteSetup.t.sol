// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GhoToken} from "@aave/gho-core/gho/GhoToken.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {stdError} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {TokenPool} from "../../pools/TokenPool.sol";
import {Router} from "../../Router.sol";
import {EVM2EVMOnRamp} from "../../onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOffRamp} from "../../offRamp/EVM2EVMOffRamp.sol";
import {BurnMintERC677} from "../../../shared/token/ERC677/BurnMintERC677.sol";
import {BurnMintTokenPool} from "../../pools/BurnMintTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {RateLimiter} from "../../libraries/RateLimiter.sol";
import {RouterSetup} from "../router/RouterSetup.t.sol";

contract GHOTokenPoolRemoteSetup is RouterSetup {
  event Transfer(address indexed from, address indexed to, uint256 value);
  event TokensConsumed(uint256 tokens);
  event Burned(address indexed sender, uint256 amount);

  BurnMintERC677 internal s_burnMintERC677;
  address internal s_burnMintOffRamp = makeAddr("burn_mint_offRamp");
  address internal s_burnMintOnRamp = makeAddr("burn_mint_onRamp");

  UpgradeableBurnMintTokenPool internal s_pool;

  address internal AAVE_DAO = makeAddr("AAVE_DAO");
  address internal PROXY_ADMIN = makeAddr("PROXY_ADMIN");

  function setUp() public virtual override {
    RouterSetup.setUp();

    // GHO deployment
    GhoToken ghoToken = new GhoToken(AAVE_DAO);
    s_burnMintERC677 = BurnMintERC677(address(ghoToken));

    s_pool = UpgradeableBurnMintTokenPool(
      _deployUpgradeableBurnMintTokenPool(
        address(s_burnMintERC677),
        address(s_mockARM),
        address(s_sourceRouter),
        AAVE_DAO,
        PROXY_ADMIN
      )
    );

    // Give mint and burn privileges to source TokenPool (GHO-specific related)
    vm.stopPrank();
    vm.startPrank(AAVE_DAO);
    GhoToken(address(s_burnMintERC677)).grantRole(
      GhoToken(address(s_burnMintERC677)).FACILITATOR_MANAGER_ROLE(),
      AAVE_DAO
    );
    GhoToken(address(s_burnMintERC677)).addFacilitator(address(s_pool), "TokenPool", type(uint128).max);
    vm.stopPrank();

    _applyChainUpdates(address(s_pool));
  }

  function _applyChainUpdates(address pool) internal {
    TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
    chains[0] = TokenPool.ChainUpdate({
      remoteChainSelector: DEST_CHAIN_SELECTOR,
      allowed: true,
      outboundRateLimiterConfig: getOutboundRateLimiterConfig(),
      inboundRateLimiterConfig: getInboundRateLimiterConfig()
    });

    vm.startPrank(AAVE_DAO);
    UpgradeableBurnMintTokenPool(pool).applyChainUpdates(chains);
    vm.stopPrank();
    vm.startPrank(OWNER);

    Router.OnRamp[] memory onRampUpdates = new Router.OnRamp[](1);
    onRampUpdates[0] = Router.OnRamp({destChainSelector: DEST_CHAIN_SELECTOR, onRamp: s_burnMintOnRamp});
    Router.OffRamp[] memory offRampUpdates = new Router.OffRamp[](1);
    offRampUpdates[0] = Router.OffRamp({sourceChainSelector: DEST_CHAIN_SELECTOR, offRamp: s_burnMintOffRamp});
    s_sourceRouter.applyRampUpdates(onRampUpdates, new Router.OffRamp[](0), offRampUpdates);
  }

  function _deployUpgradeableBurnMintTokenPool(
    address ghoToken,
    address arm,
    address router,
    address owner,
    address proxyAdmin
  ) internal returns (address) {
    // Deploy BurnMintTokenPool for GHO token on source chain
    UpgradeableBurnMintTokenPool tokenPoolImpl = new UpgradeableBurnMintTokenPool(ghoToken, arm, router);
    // Imple init
    tokenPoolImpl.initialize(owner, router);
    // proxy deploy and init
    bytes memory tokenPoolInitParams = abi.encodeWithSignature("initialize(address,address)", owner, router);
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

  function _inflateFacilitatorLevel(address tokenPool, address ghoToken, uint256 amount) internal {
    vm.stopPrank();
    vm.startPrank(tokenPool);
    BurnMintERC677(ghoToken).mint(address(0), amount);
    vm.stopPrank();
    vm.startPrank(OWNER);
  }
}
