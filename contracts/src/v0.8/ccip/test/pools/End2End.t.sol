// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../helpers/MerkleHelper.sol";
import "../commitStore/CommitStore.t.sol";
import "../onRamp/EVM2EVMOnRampSetup.t.sol";
import "../offRamp/EVM2EVMOffRampSetup.t.sol";

contract E2E is EVM2EVMOnRampSetup, CommitStoreSetup, EVM2EVMOffRampSetup {
  using Internal for Internal.EVM2EVMMessage;

  function setUp() public virtual override(EVM2EVMOnRampSetup, CommitStoreSetup, EVM2EVMOffRampSetup) {
    EVM2EVMOnRampSetup.setUp();
    CommitStoreSetup.setUp();
    EVM2EVMOffRampSetup.setUp();

    deployOffRamp(s_commitStore, s_destRouter, address(0));
  }
}
