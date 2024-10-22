pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableLockReleaseTokenPool_Sepolia} from "../../src/v0.8/ccip/test/pools/GHO/fork/GhoTokenPoolMigrate1_4To1_5/LegacyTestnetTokenPools/UpgradeableLockReleaseTokenPool_Sepolia.sol";

/// Usage
/// Upgrade Implementation: forge script script/ghoCcipMigration/Sepolia.s.sol --fork-url sepolia --sig "upgrade()" --etherscan-verifier-url https://api-sepolia.etherscan.io/api --account <ProxyAdminAccount>
/// Set Proxy Pool: forge script script/ghoCcipMigration/Sepolia.s.sol --fork-url sepolia --sig "setProxyPool()" --account <TokenPoolOwnerAccount>
contract TestnetMigration is Script {
  struct StaticParams {
    address token;
    address armProxy;
    bool allowListEnabled;
    bool acceptLiquidity;
  }

  UpgradeableLockReleaseTokenPool_Sepolia private tokenPoolProxy;

  address private constant PROXY_POOL = 0x14A3298f667CCB3ad4B77878d80b353f6A10F183; // match address

  error InvalidChain(uint256 current);
  error InvalidSigner(address who, address expected);

  modifier onlySepolia() {
    if (block.chainid != 11155111) revert InvalidChain(block.chainid);
    _;
  }

  function setUp() public {
    tokenPoolProxy = UpgradeableLockReleaseTokenPool_Sepolia(0x7768248E1Ff75612c18324bad06bb393c1206980);
  }

  function upgrade() public onlySepolia {
    StaticParams memory params = StaticParams({
      token: address(tokenPoolProxy.getToken()),
      armProxy: tokenPoolProxy.getArmProxy(),
      allowListEnabled: tokenPoolProxy.getAllowListEnabled(),
      acceptLiquidity: tokenPoolProxy.canAcceptLiquidity()
    });

    uint256 bridgedAmount = tokenPoolProxy.getCurrentBridgedAmount();
    address router = tokenPoolProxy.getRouter();

    console.log("StaticParams.token: \t\t", params.token);
    console.log("StaticParams.armProxy: \t", params.armProxy);
    console.log("StaticParams.allowListEnabled:", params.allowListEnabled);
    console.log("StaticParams.acceptLiquidity: ", params.acceptLiquidity);

    // deploy implementation
    vm.broadcast();
    address newPool = _deployLockReleaseTokenPool(params);
    console.log("newPool: \t\t\t", newPool);

    // sanity storage checks
    assert(tokenPoolProxy.getCurrentBridgedAmount() == bridgedAmount);
    assert(tokenPoolProxy.getRouter() == router);
    // static params checks
    assert(address(tokenPoolProxy.getToken()) == params.token);
    assert(tokenPoolProxy.getArmProxy() == params.armProxy);
    assert(tokenPoolProxy.getAllowListEnabled() == params.allowListEnabled);
    assert(tokenPoolProxy.canAcceptLiquidity() == params.acceptLiquidity);

    // upgrade proxy
    vm.broadcast();
    TransparentUpgradeableProxy(payable(address(tokenPoolProxy))).upgradeTo(newPool);

    address proxyPool = tokenPoolProxy.getProxyPool();
    console.log("proxyPool: \t\t\t", proxyPool);
  }

  function setProxyPool() public onlySepolia {
    console.log("Setting proxy pool to:", PROXY_POOL);

    vm.broadcast();
    tokenPoolProxy.setProxyPool(PROXY_POOL);

    assert(tokenPoolProxy.getProxyPool() == PROXY_POOL);
  }

  function _deployLockReleaseTokenPool(StaticParams memory params) internal returns (address) {
    UpgradeableLockReleaseTokenPool_Sepolia poolImpl = new UpgradeableLockReleaseTokenPool_Sepolia(
      params.token,
      params.armProxy,
      params.allowListEnabled,
      params.acceptLiquidity
    );
    return address(poolImpl);
  }
}
