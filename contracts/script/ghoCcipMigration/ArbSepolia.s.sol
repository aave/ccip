pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableBurnMintTokenPool_ArbSepolia} from "../../src/v0.8/ccip/test/pools/GHO/fork/GhoTokenPoolMigrate1_4To1_5/LegacyTestnetTokenPools/UpgradeableBurnMintTokenPool_ArbSepolia.sol";

/// Usage
/// Upgrade Implementation: forge script script/ghoCcipMigration/ArbSepolia.s.sol --fork-url arb_sepolia --sig "upgrade()" --etherscan-verifier-url https://api-sepolia.etherscan.io/api --account <ProxyAdminAccount>
/// Set Proxy Pool: forge script script/ghoCcipMigration/ArbSepolia.s.sol --fork-url arb_sepolia --sig "setProxyPool()" --account <TokenPoolOwnerAccount>

contract TestnetMigration is Script {
  struct StaticParams {
    address token;
    address armProxy;
    bool allowListEnabled;
  }

  UpgradeableBurnMintTokenPool_ArbSepolia private tokenPoolProxy;

  address private constant PROXY_POOL = 0x2BDbDCC0957E8d9f5Eb1Fe8E1Bc0d7F57AD1C897; // match address

  error InvalidChain(uint256 current);
  error InvalidSigner(address who, address expected);

  modifier onlyArbSepolia() {
    if (block.chainid != 421614) revert InvalidChain(block.chainid);
    _;
  }

  function setUp() public {
    tokenPoolProxy = UpgradeableBurnMintTokenPool_ArbSepolia(0x3eC2b6F818B72442fc36561e9F930DD2b60957D2);
  }

  function upgrade() public onlyArbSepolia {
    StaticParams memory params = StaticParams({
      token: address(tokenPoolProxy.getToken()),
      armProxy: tokenPoolProxy.getArmProxy(),
      allowListEnabled: tokenPoolProxy.getAllowListEnabled()
    });

    address router = tokenPoolProxy.getRouter();

    console.log("StaticParams.token: \t\t", params.token);
    console.log("StaticParams.armProxy: \t", params.armProxy);
    console.log("StaticParams.allowListEnabled:", params.allowListEnabled);

    // deploy implementation
    vm.broadcast();
    address newPool = _deployBurnMintTokenPool(params);
    console.log("newPool: \t\t\t", newPool);

    // sanity storage check
    assert(tokenPoolProxy.getRouter() == router);
    // static params checks
    assert(address(tokenPoolProxy.getToken()) == params.token);
    assert(tokenPoolProxy.getArmProxy() == params.armProxy);
    assert(tokenPoolProxy.getAllowListEnabled() == params.allowListEnabled);

    // upgrade proxy
    vm.broadcast();
    TransparentUpgradeableProxy(payable(address(tokenPoolProxy))).upgradeTo(newPool);
  }

  function setProxyPool() public onlyArbSepolia {
    console.log("Setting proxy pool to:", PROXY_POOL);

    vm.broadcast();
    tokenPoolProxy.setProxyPool(PROXY_POOL);

    assert(tokenPoolProxy.getProxyPool() == PROXY_POOL);
  }

  function _deployBurnMintTokenPool(StaticParams memory params) internal returns (address) {
    UpgradeableBurnMintTokenPool_ArbSepolia poolImpl = new UpgradeableBurnMintTokenPool_ArbSepolia(
      params.token,
      params.armProxy,
      params.allowListEnabled
    );
    return address(poolImpl);
  }
}
