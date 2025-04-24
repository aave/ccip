// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script, console2 as console} from "forge-std/Script.sol";

import {UpgradeableBurnMintTokenPool} from "./../src/v0.8/ccip/pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {ITransparentProxyFactory} from "solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol";
import {IERC20Metadata} from "solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol";

interface IProxyAdmin {
  function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
}

contract DeployUpgradableBurnMintTokenPool is Script {
  function run() external {
    IERC20Metadata GHO_TOKEN = IERC20Metadata(vm.promptAddress("GHO_TOKEN"));
    uint8 TOKEN_DECIMALS = _validateTokenAndFetchDecimals(GHO_TOKEN);
    ITransparentProxyFactory PROXY_FACTORY = ITransparentProxyFactory(vm.promptAddress("TRANSPARENT_PROXY_FACTORY"));
    address OWNER = vm.promptAddress("OWNER");
    address ROUTER = vm.promptAddress("ROUTER");
    address RMN_PROXY = vm.promptAddress("RMN_PROXY");

    address[] memory ALLOW_LIST = new address[](0);
    bool ALLOW_LIST_ENABLED = false;

    vm.startBroadcast();
    address tokenPool = address(
      new UpgradeableBurnMintTokenPool(address(GHO_TOKEN), TOKEN_DECIMALS, RMN_PROXY, ALLOW_LIST_ENABLED)
    );
    address tokenPoolProxy = PROXY_FACTORY.create(
      tokenPool,
      OWNER,
      abi.encodeCall(UpgradeableBurnMintTokenPool.initialize, (OWNER, ALLOW_LIST, ROUTER))
    );
    vm.stopBroadcast();

    console.log("tokenPoolProxy: ", tokenPoolProxy);
    console.log("tokenPool: ", tokenPool);

    _validateProxyAdminVersion(tokenPoolProxy);
  }

  function _validateTokenAndFetchDecimals(IERC20Metadata token) internal view returns (uint8) {
    require(_cmp(token.name(), "GHO"), "InvalidToken");
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
