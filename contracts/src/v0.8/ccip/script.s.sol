// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {UpgradeableLockReleaseTokenPool} from "./pools/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "./pools/UpgradeableBurnMintTokenPool.sol";
import {UpgradeableTokenPool} from "./pools/UpgradeableTokenPool.sol";


contract DeployLockReleaseTokenPool is Script {
  // ETH SEPOLIA - 11155111
  address GHO_TOKEN = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60;
  address PROXY_ADMIN = 0xfA0e305E0f46AB04f00ae6b5f4560d61a2183E00;
  address ARM_PROXY = 0xba3f6251de62dED61Ff98590cB2fDf6871FbB991;
  address ROUTER = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
  address TOKEN_POOL_OWNER = 0xa4b184737418B3014b3B1b1f0bE6700Bd9640FfE;

  // ARB SEPOLIA - 421614
  //   address GHO_TOKEN = 0xb13Cfa6f8B2Eed2C37fB00fF0c1A59807C585810;
  //   address PROXY_ADMIN = 0xfA0e305E0f46AB04f00ae6b5f4560d61a2183E00;
  //   address ARM_PROXY = 0x9527E2d01A3064ef6b50c1Da1C0cC523803BCFF2;
  //   address ROUTER = 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;
  //   address TOKEN_POOL_OWNER = 0xa4b184737418B3014b3B1b1f0bE6700Bd9640FfE;

  // BASE SEPOLIA - 84532
  //   address GHO_TOKEN = 0x7CFa3f3d1cded0Da930881c609D4Dbf0012c14Bb;
  //   address PROXY_ADMIN = 0xfA0e305E0f46AB04f00ae6b5f4560d61a2183E00;
  //   address ARM_PROXY = 0x99360767a4705f68CcCb9533195B761648d6d807;
  //   address ROUTER = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
  //   address TOKEN_POOL_OWNER = 0xa4b184737418B3014b3B1b1f0bE6700Bd9640FfE;

  // FUJI - 43113
  //   address GHO_TOKEN = 0x9c04928Cc678776eC1C1C0E46ecC03a5F47A7723;
  //   address PROXY_ADMIN = 0xfA0e305E0f46AB04f00ae6b5f4560d61a2183E00;
  //   address ARM_PROXY = 0xAc8CFc3762a979628334a0E4C1026244498E821b;
  //   address ROUTER = 0xF694E193200268f9a4868e4Aa017A0118C9a8177;
  //   address TOKEN_POOL_OWNER = 0xa4b184737418B3014b3B1b1f0bE6700Bd9640FfE;

  function run() external {
    console2.log('Block Number: ', block.number);
    vm.startBroadcast();

    UpgradeableLockReleaseTokenPool tokenPoolImpl = new UpgradeableLockReleaseTokenPool(GHO_TOKEN, ARM_PROXY, false, true);
    // Imple init
    address[] memory emptyArray = new address[](0);
    tokenPoolImpl.initialize(TOKEN_POOL_OWNER, emptyArray, ROUTER, 10e18);
    // proxy deploy and init
    bytes memory tokenPoolInitParams = abi.encodeWithSignature(
      "initialize(address,address[],address,uint256)",
      TOKEN_POOL_OWNER,
      emptyArray,
      ROUTER,
      10e18
    );
    TransparentUpgradeableProxy tokenPoolProxy = new TransparentUpgradeableProxy(
      address(tokenPoolImpl),
      PROXY_ADMIN,
      tokenPoolInitParams
    );

    vm.stopBroadcast();
    // Manage ownership
    // UpgradeableLockReleaseTokenPool(address(tokenPoolProxy)).acceptOwnership();

  }
}

contract Accept is Script {

  function run() external {
    console2.log('Block Number: ', block.number);
    vm.startBroadcast();

    console2.log(UpgradeableLockReleaseTokenPool(0x50A715d63bDcd5455a3308932a624263d170Dd74).getBridgeLimit());
    
    // Manage ownership
    UpgradeableLockReleaseTokenPool(0x50A715d63bDcd5455a3308932a624263d170Dd74).acceptOwnership();
    vm.stopBroadcast();

  }
}

