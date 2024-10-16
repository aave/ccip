// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../../../../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {UpgradeableLockReleaseTokenPool} from "../../../../../pools/GHO/UpgradeableLockReleaseTokenPool.sol";
import {UpgradeableBurnMintTokenPool} from "../../../../../pools/GHO/UpgradeableBurnMintTokenPool.sol";
import {IRouterClient} from "../../../../../interfaces/IRouterClient.sol";
import {Client} from "../../../../../libraries/Client.sol";

contract ForkBase is Test {
  error CallerIsNotARampOnRouter(address caller);

  struct L1 {
    UpgradeableLockReleaseTokenPool tokenPool;
    IRouterClient router;
    IERC20 token;
    address proxyPool;
    uint64 chainSelector;
    uint forkId;
  }
  struct L2 {
    UpgradeableBurnMintTokenPool tokenPool;
    IRouterClient router;
    IERC20 token;
    address proxyPool;
    uint64 chainSelector;
    uint forkId;
  }

  L1 internal l1;
  L2 internal l2;

  address internal alice = makeAddr("alice");

  function setUp() public virtual {
    l1.forkId = vm.createFork("https://sepolia.gateway.tenderly.co", 6884195);
    l2.forkId = vm.createFork("https://arbitrum-sepolia.gateway.tenderly.co", 89058935);

    vm.selectFork(l1.forkId);
    l1.tokenPool = UpgradeableLockReleaseTokenPool(0x7768248E1Ff75612c18324bad06bb393c1206980);
    l1.proxyPool = 0x14A3298f667CCB3ad4B77878d80b353f6A10F183;
    l1.router = IRouterClient(l1.tokenPool.getRouter());
    l2.chainSelector = l1.tokenPool.getSupportedChains()[0];
    l1.token = l1.tokenPool.getToken();
    vm.prank(alice);
    l1.token.approve(address(l1.router), type(uint256).max);
    deal(address(l1.token), alice, 1000e18);
    deal(alice, 1000e18);

    vm.selectFork(l2.forkId);
    l2.tokenPool = UpgradeableBurnMintTokenPool(0x3eC2b6F818B72442fc36561e9F930DD2b60957D2);
    l2.proxyPool = 0x2BDbDCC0957E8d9f5Eb1Fe8E1Bc0d7F57AD1C897;
    l2.router = IRouterClient(l2.tokenPool.getRouter());
    l1.chainSelector = l2.tokenPool.getSupportedChains()[0];
    l2.token = l2.tokenPool.getToken();
    vm.prank(alice);
    l2.token.approve(address(l2.router), type(uint256).max);
    deal(address(l2.token), alice, 1000e18);
    deal(alice, 1000e18);

    vm.selectFork(l1.forkId);
    assertEq(address(l1.router), 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
    assertEq(l1.chainSelector, 16015286601757825753);
    assertEq(address(l1.token), 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60);
    assertEq(l1.token.balanceOf(alice), 1000e18);
    assertEq(l1.proxyPool, 0x14A3298f667CCB3ad4B77878d80b353f6A10F183);

    vm.selectFork(l2.forkId);
    assertEq(address(l2.router), 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165);
    assertEq(l2.chainSelector, 3478487238524512106);
    assertEq(address(l2.token), 0xb13Cfa6f8B2Eed2C37fB00fF0c1A59807C585810);
    assertEq(l2.token.balanceOf(alice), 1000e18);
    assertEq(l2.proxyPool, 0x2BDbDCC0957E8d9f5Eb1Fe8E1Bc0d7F57AD1C897);

    _label();
  }

  function _selectForkAndStartPrank(uint forkId) internal {
    vm.selectFork(forkId);
    vm.startPrank(alice);
  }

  function _label() internal {
    vm.label(address(l1.tokenPool), "l1.tokenPool");
    vm.label(address(l1.token), "l1.token");
    vm.label(address(l1.router), "l1.router");
    vm.label(address(l1.proxyPool), "l1.proxyPool");

    vm.label(address(l2.tokenPool), "l2.tokenPool");
    vm.label(address(l2.token), "l2.token");
    vm.label(address(l2.router), "l2.router");
    vm.label(address(l2.proxyPool), "l2.proxyPool");
  }
}

contract ForkBaseTest is ForkBase {
  function setUp() public override {
    super.setUp();
  }

  function test_currentSetupBroken() public {
    uint256 amount = 10e18;
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: new bytes(0),
      tokenAmounts: new Client.EVMTokenAmount[](1),
      feeToken: address(0), // will be paying in native tokens for tests
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
    });
    message.tokenAmounts[0].token = address(l1.token);
    message.tokenAmounts[0].amount = amount;

    vm.selectFork(l1.forkId);
    uint256 feeTokenAmount = l1.router.getFee(l2.chainSelector, message);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, l1.proxyPool));
    l1.router.ccipSend{value: feeTokenAmount}(l2.chainSelector, message);

    vm.selectFork(l2.forkId);
    message.tokenAmounts[0].token = address(l2.token);
    feeTokenAmount = l2.router.getFee(l1.chainSelector, message);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, l2.proxyPool));
    l2.router.ccipSend{value: feeTokenAmount}(l1.chainSelector, message);
  }
}
