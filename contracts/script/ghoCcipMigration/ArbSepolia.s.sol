pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableBurnMintTokenPool_ArbSepolia} from "../../src/v0.8/ccip/test/pools/GHO/fork/GhoTokenPoolMigrate1_4To1_5/LegacyTestnetTokenPools/UpgradeableBurnMintTokenPool_ArbSepolia.sol";

interface Vm {
  function promptSecretUint(string memory) external returns (uint256);
}

// forge script script/ghoCcipMigration/ArbSepolia.s.sol --fork-url arb_sepolia --sig "run(address)" 0x2BDbDCC0957E8d9f5Eb1Fe8E1Bc0d7F57AD1C897 --etherscan-verifier-url https://api-sepolia.arbiscan.io/api
contract TestnetMigration is Script {
  struct StaticParams {
    address token;
    address armProxy;
    bool allowListEnabled;
  }

  uint256 private proxyAdminPk;
  uint256 private ownerPk;
  UpgradeableBurnMintTokenPool_ArbSepolia private tokenPoolProxy;

  address private constant PROXY_POOL = 0x2BDbDCC0957E8d9f5Eb1Fe8E1Bc0d7F57AD1C897; // match address

  error InvalidChain(uint256 current);
  error InvalidSigner(address who, address expected);

  modifier onlyArbSepolia() {
    if (block.chainid != 421614) revert InvalidChain(block.chainid);
    _;
  }

  function setUp() public {
    // proxyAdminPk = vm.envUint("proxyAdminPk");
    // ownerPk = vm.envUint("ownerPk");
    proxyAdminPk = Vm(address(vm)).promptSecretUint("proxyAdminPk");
    ownerPk = Vm(address(vm)).promptSecretUint("ownerPk");

    tokenPoolProxy = UpgradeableBurnMintTokenPool_ArbSepolia(0x3eC2b6F818B72442fc36561e9F930DD2b60957D2);

    address proxyAdminAddress = address(
      uint160(uint256(vm.load(address(tokenPoolProxy), bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1))))
    );
    if (vm.addr(proxyAdminPk) != proxyAdminAddress) revert InvalidSigner(vm.addr(proxyAdminPk), proxyAdminAddress);
    if (vm.addr(ownerPk) != tokenPoolProxy.owner()) revert InvalidSigner(vm.addr(ownerPk), tokenPoolProxy.owner());
  }

  function run(address proxyPool) public onlyArbSepolia {
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
    vm.broadcast(ownerPk);
    address newPool = _deployBurnMintTokenPool(params);
    console.log("newPool: \t\t\t", newPool);

    // upgrade proxy
    vm.broadcast(proxyAdminPk);
    TransparentUpgradeableProxy(payable(address(tokenPoolProxy))).upgradeTo(newPool);

    // set proxyPool
    vm.broadcast(ownerPk);
    tokenPoolProxy.setProxyPool(proxyPool);

    assert(tokenPoolProxy.getProxyPool() == proxyPool);

    // sanity storage check
    assert(tokenPoolProxy.getRouter() == router);
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
