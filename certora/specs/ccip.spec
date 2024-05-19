/*
    This is a Specification File for Smart Contract Verification with the Certora Prover.
    This file is run with ???
*/

//using ATokenHarness as _aToken;


methods {
  function getCurrentBridgedAmount() external returns (uint256) envfree;
  function getBridgeLimit() external returns (uint256) envfree;
}



rule sanity {
  env e;
  calldataarg arg;
  method f;
  f(e, arg);
  satisfy true;
}



invariant currentBridge_LEQ_bridgeLimit()
  getCurrentBridgedAmount() <= getBridgeLimit();
