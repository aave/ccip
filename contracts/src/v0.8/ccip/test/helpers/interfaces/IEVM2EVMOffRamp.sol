pragma solidity ^0.8.0;

import {ITypeAndVersion} from "../../../../shared/interfaces/ITypeAndVersion.sol";
import {IAny2EVMOffRamp} from "../../../interfaces/IAny2EVMOffRamp.sol";
import {Internal} from "../../../libraries/Internal.sol";

interface IEVM2EVMOffRamp_1_2 is IAny2EVMOffRamp, ITypeAndVersion {
  function executeSingleMessage(Internal.EVM2EVMMessage memory message, bytes[] memory offchainTokenData) external;
}

interface IEVM2EVMOffRamp_1_5 is IAny2EVMOffRamp, ITypeAndVersion {
  function executeSingleMessage(
    Internal.EVM2EVMMessage calldata message,
    bytes[] calldata offchainTokenData,
    uint32[] memory tokenGasOverrides
  ) external;
}
