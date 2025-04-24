// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {UpgradeableBurnMintTokenPool} from "./../src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {ITypeAndVersion} from "./../src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {ITransparentProxyFactory} from "solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol";
import {IERC20Metadata} from "solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol";

interface IProxyAdmin {
  function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
}

struct Config {
  address GHO_TOKEN;
  address OWNER;
  address PROXY_FACTORY;
  address RMN_PROXY;
  address ROUTER;
}

/// @notice Deploys UpgradeableBurnMintTokenPool behind a transparent upgradable proxy for GHO.
/// Pre-requisite: add parameters to config.json, the with key as `chainId` of the target network.
/// Usage: forge script DeployUpgradableBurnMintTokenPool --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify --etherscan-api-key <ETHERSCAN_API_KEY>
contract DeployUpgradableBurnMintTokenPool is Script {
  using stdJson for string;

  function run() external {
    Config memory config = _parseConfig();

    uint8 TOKEN_DECIMALS = IERC20Metadata(config.GHO_TOKEN).decimals();
    address[] memory ALLOW_LIST = new address[](0);
    bool ALLOW_LIST_ENABLED = false;

    vm.startBroadcast();
    address tokenPool = address(
      new UpgradeableBurnMintTokenPool(config.GHO_TOKEN, TOKEN_DECIMALS, config.RMN_PROXY, ALLOW_LIST_ENABLED)
    );
    address tokenPoolProxy = ITransparentProxyFactory(config.PROXY_FACTORY).create(
      tokenPool,
      config.OWNER,
      abi.encodeCall(UpgradeableBurnMintTokenPool.initialize, (config.OWNER, ALLOW_LIST, config.ROUTER))
    );
    vm.stopBroadcast();

    console.log("tokenPoolProxy: ", tokenPoolProxy);
    console.log("tokenPool:      ", tokenPool);

    _validateProxyAdminVersion(tokenPoolProxy);
  }

  function _parseConfig() internal view returns (Config memory) {
    string memory config = vm.readFile(string.concat(vm.projectRoot(), "/script/config.json"));
    return _validate(abi.decode(vm.parseJson(config, string.concat(".", vm.toString(block.chainid))), (Config)));
  }

  function _validate(Config memory config) internal view returns (Config memory) {
    require(address(config.OWNER) != address(0), "InvalidOwner");
    require(address(config.PROXY_FACTORY) != address(0), "InvalidProxyFactory");
    require(_cmp(IERC20Metadata(config.GHO_TOKEN).name(), "Gho Token"), "InvalidToken");
    require(_cmp(IERC20Metadata(config.GHO_TOKEN).symbol(), "GHO"), "InvalidToken");
    require(_cmp(ITypeAndVersion(config.RMN_PROXY).typeAndVersion(), "ARMProxy 1.0.0"), "InvalidRmnProxy");
    require(_cmp(ITypeAndVersion(config.ROUTER).typeAndVersion(), "Router 1.2.0"), "InvalidRouter");
    return config;
  }

  function _validateProxyAdminVersion(address proxy) internal view {
    IProxyAdmin proxyAdmin = _getProxyAdmin(proxy);
    require(address(proxyAdmin) != address(0), "InvalidProxyAdmin");
    require(_cmp(proxyAdmin.UPGRADE_INTERFACE_VERSION(), "5.0.0"), "InvalidProxyAdminVersion");
  }

  function _getProxyAdmin(address proxy) internal view returns (IProxyAdmin) {
    bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    return IProxyAdmin(address(uint160(uint256(vm.load(proxy, slot)))));
  }

  function _cmp(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
  }
}
