/*
    This is a Specification File for Smart Contract Verification with the Certora Prover.
    Contract name: UpgradeableLockReleaseTokenPool
*/

using SimpleERC20 as erc20;

methods {
  function getCurrentBridgedAmount() external returns (uint256) envfree;
  function getBridgeLimit() external returns (uint256) envfree;
  function owner() external returns (address) envfree;
  function getRebalancer() external returns (address) envfree;
}


rule sanity {
  env e;
  calldataarg arg;
  method f;
  f(e, arg);
  satisfy true;
}



/* ==============================================================================
   invariant: currentBridge_LEQ_bridgeLimit.
   Description: The value of s_currentBridged is LEQ than the value of s_bridgeLimit.
   Note: this may be violated if one calls to setBridgeLimit(newBridgeLimit) with 
         newBridgeLimit < s_currentBridged.
   ============================================================================*/
invariant currentBridge_LEQ_bridgeLimit()
  getCurrentBridgedAmount() <= getBridgeLimit()
  filtered { f ->
    !f.isView &&
    f.selector != sig:setBridgeLimit(uint256).selector &&
    f.selector != sig:setCurrentBridgedAmount(uint256).selector}
  {
    preserved initialize(address owner, address[] allowlist, address router, uint256 bridgeLimit) with (env e2) {
      require getCurrentBridgedAmount()==0;
    }
  }


/* ==============================================================================
   rule: withdrawLiquidity_correctness
   description: The rule checks that the balance of the contract is as expected.
   ============================================================================*/
rule withdrawLiquidity_correctness(env e) {
  uint256 amount;

  require e.msg.sender != currentContract;
  uint256 bal_before = erc20.balanceOf(e, currentContract);
  withdrawLiquidity(e, amount);
  uint256 bal_after = erc20.balanceOf(e, currentContract);

  assert (to_mathint(bal_after) == bal_before - amount);
}


/* ==============================================================================
   rule: provideLiquidity_correctness
   description: The rule checks that the balance of the contract is as expected.
   ============================================================================*/
rule provideLiquidity_correctness(env e) {
  uint256 amount;

  require e.msg.sender != currentContract;
  uint256 bal_before = erc20.balanceOf(e, currentContract);
  provideLiquidity(e, amount);
  uint256 bal_after = erc20.balanceOf(e, currentContract);

  assert (to_mathint(bal_after) == bal_before + amount);
}

definition filterSetter(method f) returns bool = f.selector != sig:setCurrentBridgedAmount(uint256).selector;

/* ==============================================================================
   rule: only_lockOrBurn_can_increase_currentBridged
   ============================================================================*/
rule only_lockOrBurn_can_increase_currentBridged(env e, method f) 
  filtered { f -> filterSetter(f)  }
{
  calldataarg args;

  uint256 curr_bridge_before = getCurrentBridgedAmount();
  f (e,args);
  uint256 curr_bridge_after = getCurrentBridgedAmount();

  assert 
    curr_bridge_after > curr_bridge_before =>
    f.selector==sig:lockOrBurn(Pool.LockOrBurnInV1).selector;
}


/* ==============================================================================
   rule: only_releaseOrMint_can_decrease_currentBridged
   ============================================================================*/
rule only_releaseOrMint_can_decrease_currentBridged(env e, method f) 
  filtered { f -> filterSetter(f) }
{
  calldataarg args;

  uint256 curr_bridge_before = getCurrentBridgedAmount();
  f (e,args);
  uint256 curr_bridge_after = getCurrentBridgedAmount();

  assert 
    curr_bridge_after < curr_bridge_before =>
    f.selector==sig:releaseOrMint(Pool.ReleaseOrMintInV1).selector;
}


/* ==============================================================================
   rule: only_bridgeLimitAdmin_or_owner_can_call_setBridgeLimit
   ============================================================================*/
rule only_bridgeLimitAdmin_or_owner_can_call_setBridgeLimit(env e) {
  uint256 newBridgeLimit;

  setBridgeLimit(e, newBridgeLimit);
  
  assert e.msg.sender==getBridgeLimitAdmin(e) || e.msg.sender==owner();
}


/* ==============================================================================
   rule: only_owner_can_call_setCurrentBridgedAmount
   ============================================================================*/
rule only_owner_can_call_setCurrentBridgedAmount(env e) {
  uint256 newBridgedAmount;

  setCurrentBridgedAmount(e, newBridgedAmount);
  
  assert e.msg.sender==owner();
}

/* ==============================================================================
   rule: only_rebalancer_can_call_provideLiquidity
   ============================================================================*/
rule only_rebalancer_can_call_provideLiquidity(env e) {
  uint256 amount;
  provideLiquidity(e, amount);
  
  assert e.msg.sender==getRebalancer();
}


/* ==============================================================================
   rule: only_rebalancer_can_call_withdrawLiquidity
   ============================================================================*/
rule only_rebalancer_can_call_withdrawLiquidity(env e) {
  uint256 amount;
  withdrawLiquidity(e, amount);
  
  assert e.msg.sender==getRebalancer();
}
