pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableLockReleaseTokenPool_Sepolia} from "../../src/v0.8/ccip/test/pools/GHO/fork/GhoTokenPoolMigrate1_4To1_5/LegacyTestnetTokenPools/UpgradeableLockReleaseTokenPool_Sepolia.sol";

interface Vm {
  function promptSecretUint(string memory) external returns (uint256);
}

// forge script script/ghoCcipMigration/Sepolia.s.sol --fork-url sepolia --sig "run(address)" 0x14A3298f667CCB3ad4B77878d80b353f6A10F183 --etherscan-verifier-url https://api-sepolia.etherscan.io/api
contract TestnetMigration is Script {
  struct StaticParams {
    address token;
    address armProxy;
    bool allowListEnabled;
    bool acceptLiquidity;
  }

  uint256 private proxyAdminPk;
  uint256 private ownerPk;
  UpgradeableLockReleaseTokenPool_Sepolia private tokenPoolProxy;

  address private constant PROXY_POOL = 0x14A3298f667CCB3ad4B77878d80b353f6A10F183; // match address

  error InvalidChain(uint256 current);
  error InvalidSigner(address who, address expected);

  modifier onlySepolia() {
    if (block.chainid != 11155111) revert InvalidChain(block.chainid);
    _;
  }

  function setUp() public {
    // proxyAdminPk = vm.envUint("proxyAdminPk");
    // ownerPk = vm.envUint("ownerPk");
    proxyAdminPk = Vm(address(vm)).promptSecretUint("proxyAdminPk");
    ownerPk = Vm(address(vm)).promptSecretUint("ownerPk");

    tokenPoolProxy = UpgradeableLockReleaseTokenPool_Sepolia(0x7768248E1Ff75612c18324bad06bb393c1206980);

    address proxyAdminAddress = address(
      uint160(uint256(vm.load(address(tokenPoolProxy), bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1))))
    );
    if (vm.addr(proxyAdminPk) != proxyAdminAddress) revert InvalidSigner(vm.addr(proxyAdminPk), proxyAdminAddress);
    if (vm.addr(ownerPk) != tokenPoolProxy.owner()) revert InvalidSigner(vm.addr(ownerPk), tokenPoolProxy.owner());
  }

  function run(address proxyPool) public onlySepolia {
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
    vm.broadcast(ownerPk);
    address newPool = _deployLockReleaseTokenPool(params);
    console.log("newPool: \t\t\t", newPool);

    // upgrade proxy
    vm.broadcast(proxyAdminPk);
    TransparentUpgradeableProxy(payable(address(tokenPoolProxy))).upgradeTo(newPool);

    // set proxyPool
    vm.broadcast(ownerPk);
    tokenPoolProxy.setProxyPool(proxyPool);

    assert(tokenPoolProxy.getProxyPool() == proxyPool);

    // sanity storage checks
    assert(tokenPoolProxy.getCurrentBridgedAmount() == bridgedAmount);
    assert(tokenPoolProxy.getRouter() == router);
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
