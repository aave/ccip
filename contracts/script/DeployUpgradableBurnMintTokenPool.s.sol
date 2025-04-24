// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {UpgradeableBurnMintTokenPool} from "./../src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {ITransparentProxyFactory} from "solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol";
import {IERC20Metadata} from "solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol";

interface IProxyAdmin {
  function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
}

struct Config {
  IERC20Metadata GHO_TOKEN;
  address OWNER;
  ITransparentProxyFactory PROXY_FACTORY;
  address RMN_PROXY;
  address ROUTER;
}

contract DeployUpgradableBurnMintTokenPool is Script {
  using stdJson for string;

  function run() external {
    Config memory config = this.parseConfig();
    uint8 TOKEN_DECIMALS = _validateTokenAndFetchDecimals(config.GHO_TOKEN);

    address[] memory ALLOW_LIST = new address[](0);
    bool ALLOW_LIST_ENABLED = false;

    vm.startBroadcast();
    address tokenPool = address(
      new UpgradeableBurnMintTokenPool(address(config.GHO_TOKEN), TOKEN_DECIMALS, config.RMN_PROXY, ALLOW_LIST_ENABLED)
    );
    address tokenPoolProxy = config.PROXY_FACTORY.create(
      tokenPool,
      config.OWNER,
      abi.encodeCall(UpgradeableBurnMintTokenPool.initialize, (config.OWNER, ALLOW_LIST, config.ROUTER))
    );
    vm.stopBroadcast();

    console.log("tokenPoolProxy: ", tokenPoolProxy);
    console.log("tokenPool: ", tokenPool);

    _validateProxyAdminVersion(tokenPoolProxy);
  }

  function parseConfig() external view returns (Config memory) {
    string memory config = vm.readFile(string.concat(vm.projectRoot(), "/script/config.json"));
    return abi.decode(vm.parseJson(config, string.concat(".", vm.toString(block.chainid))), (Config));
  }

  function _validateTokenAndFetchDecimals(IERC20Metadata token) internal view returns (uint8) {
    require(_cmp(token.name(), "Gho Token"), "InvalidToken");
    require(_cmp(token.symbol(), "GHO"), "InvalidToken");
    return token.decimals();
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
