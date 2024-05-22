/*
    This is a Specification File for Smart Contract Verification with the Certora Prover.
    This file is run with ???
*/

//using ATokenHarness as _aToken;
using SimpleERC20 as erc20;


methods {
  function getCurrentBridgedAmount() external returns (uint256) envfree;
  function getBridgeLimit() external returns (uint256) envfree;
  //  function withdrawLiquidity(uint256) external envfree;
  function getRebalancer() external returns (address) envfree;
  //  function getToken() external returns (address) envfree;
}



rule sanity {
  env e;
  calldataarg arg;
  method f;
  f(e, arg);
  satisfy true;
}


invariant currentBridge_LEQ_bridgeLimit()
  getCurrentBridgedAmount() <= getBridgeLimit()
  filtered { f ->
    !f.isView &&
    f.selector != sig:setBridgeLimit(uint256).selector}
  {
    preserved initialize(address owner, address[] allowlist, address router, uint256 bridgeLimit) with (env e2) {
      require getCurrentBridgedAmount()==0;
    }
  }


rule withdrawLiquidity_correctness(env e) {
  uint256 amount;

  require e.msg.sender != currentContract;
  uint256 bal_before = erc20.balanceOf(e, currentContract);
  withdrawLiquidity(e, amount);
  uint256 bal_after = erc20.balanceOf(e, currentContract);

  assert e.msg.sender == getRebalancer();
  assert (to_mathint(bal_after) == bal_before - amount);
}


rule provideLiquidity_correctness(env e) {
  uint256 amount;

  require e.msg.sender != currentContract;
  uint256 bal_before = erc20.balanceOf(e, currentContract);
  provideLiquidity(e, amount);
  uint256 bal_after = erc20.balanceOf(e, currentContract);

  assert e.msg.sender == getRebalancer();
  assert (to_mathint(bal_after) == bal_before + amount);
}
