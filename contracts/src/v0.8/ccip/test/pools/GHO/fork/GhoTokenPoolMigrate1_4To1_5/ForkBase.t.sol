// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../../../../../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ITypeAndVersion} from "../../../../../../shared/interfaces/ITypeAndVersion.sol";
import {IRouterClient} from "../../../../../interfaces/IRouterClient.sol";
import {IEVM2AnyOnRamp} from "../../../../../interfaces/IEVM2AnyOnRamp.sol";
import {IAny2EVMOffRamp} from "../../../../../interfaces/IAny2EVMOffRamp.sol";
import {IRouter as IRouterBase} from "../../../../../interfaces/IRouter.sol";
import {Client} from "../../../../../libraries/Client.sol";
import {Internal} from "../../../../../libraries/Internal.sol";
import {UpgradeableLockReleaseTokenPool_Sepolia} from "./LegacyTestnetTokenPools/UpgradeableLockReleaseTokenPool_Sepolia.sol";
import {UpgradeableBurnMintTokenPool_ArbSepolia} from "./LegacyTestnetTokenPools/UpgradeableBurnMintTokenPool_ArbSepolia.sol";

interface IRouter is IRouterClient, IRouterBase {
  struct OffRamp {
    uint64 sourceChainSelector;
    address offRamp;
  }
  function getWrappedNative() external view returns (address);
  function isOffRamp(uint64, address) external view returns (bool);
  function getOffRamps() external view returns (OffRamp[] memory);
}

struct SourceTokenData {
  bytes sourcePoolAddress;
  bytes destTokenAddress;
  bytes extraData;
  uint32 destGasAmount;
}

contract ForkBase is Test {
  error CallerIsNotARampOnRouter(address caller);
  event CCIPSendRequested(Internal.EVM2EVMMessage message);

  struct L1 {
    UpgradeableLockReleaseTokenPool_Sepolia tokenPool;
    IRouter router;
    IERC20 token;
    IEVM2AnyOnRamp EVM2EVMOnRamp1_2;
    IEVM2AnyOnRamp EVM2EVMOnRamp1_5;
    IAny2EVMOffRamp EVM2EVMOffRamp1_2;
    IAny2EVMOffRamp EVM2EVMOffRamp1_5;
    address proxyPool;
    uint64 chainSelector;
    bytes32 metadataHash;
    uint256 forkId;
  }
  struct L2 {
    UpgradeableBurnMintTokenPool_ArbSepolia tokenPool;
    IRouter router;
    IERC20 token;
    IEVM2AnyOnRamp EVM2EVMOnRamp1_2;
    IEVM2AnyOnRamp EVM2EVMOnRamp1_5;
    IAny2EVMOffRamp EVM2EVMOffRamp1_2;
    IAny2EVMOffRamp EVM2EVMOffRamp1_5;
    address proxyPool;
    uint64 chainSelector;
    bytes32 metadataHash;
    uint256 forkId;
  }

  L1 internal l1;
  L2 internal l2;

  address internal alice = makeAddr("alice");

  uint256 internal constant BLOCK_AFTER_MIGRATION_L1 = 6884195;
  uint256 internal constant BLOCK_AFTER_MIGRATION_L2 = 89058935;

  function setUp() public virtual {
    l1.forkId = vm.createFork(vm.rpcUrl("sepolia"), BLOCK_AFTER_MIGRATION_L1);
    l2.forkId = vm.createFork(vm.rpcUrl("arb_sepolia"), BLOCK_AFTER_MIGRATION_L2);

    vm.selectFork(l1.forkId);
    l1.tokenPool = UpgradeableLockReleaseTokenPool_Sepolia(0x7768248E1Ff75612c18324bad06bb393c1206980);
    l1.proxyPool = 0x14A3298f667CCB3ad4B77878d80b353f6A10F183;
    l1.router = IRouter(l1.tokenPool.getRouter());
    l2.chainSelector = l1.tokenPool.getSupportedChains()[0];
    l1.token = l1.tokenPool.getToken();
    l1.EVM2EVMOnRamp1_2 = IEVM2AnyOnRamp(0xe4Dd3B16E09c016402585a8aDFdB4A18f772a07e); // legacy on ramp
    l1.EVM2EVMOnRamp1_5 = IEVM2AnyOnRamp(l1.router.getOnRamp(l2.chainSelector));
    l1.EVM2EVMOffRamp1_2 = IAny2EVMOffRamp(0xF18896AB20a09A29e64fdEbA99FDb8EC328f43b1);
    l1.EVM2EVMOffRamp1_5 = IAny2EVMOffRamp(0xD2f5edfD4561d6E7599F6c6888Bd353cAFd0c55E);
    vm.prank(alice);
    l1.token.approve(address(l1.router), type(uint256).max);
    deal(address(l1.token), alice, 1000e18);
    deal(alice, 1000e18);

    vm.selectFork(l2.forkId);
    l2.tokenPool = UpgradeableBurnMintTokenPool_ArbSepolia(0x3eC2b6F818B72442fc36561e9F930DD2b60957D2);
    l2.proxyPool = 0x2BDbDCC0957E8d9f5Eb1Fe8E1Bc0d7F57AD1C897;
    l2.router = IRouter(l2.tokenPool.getRouter());
    l1.chainSelector = l2.tokenPool.getSupportedChains()[0];
    l2.token = l2.tokenPool.getToken();
    l2.EVM2EVMOnRamp1_2 = IEVM2AnyOnRamp(0x4205E1Ca0202A248A5D42F5975A8FE56F3E302e9); // legacy on ramp
    l2.EVM2EVMOnRamp1_5 = IEVM2AnyOnRamp(l2.router.getOnRamp(l1.chainSelector));
    l2.EVM2EVMOffRamp1_2 = IAny2EVMOffRamp(0x1c71f141b4630EBE52d6aF4894812960abE207eB);
    l2.EVM2EVMOffRamp1_5 = IAny2EVMOffRamp(0xBed6e9131916d724418C8a6FE810F727302a5c00);
    vm.prank(alice);
    l2.token.approve(address(l2.router), type(uint256).max);
    deal(address(l2.token), alice, 1000e18);
    deal(alice, 1000e18);

    l1.metadataHash = _generateMetadataHash(l1.chainSelector);
    l2.metadataHash = _generateMetadataHash(l2.chainSelector);

    vm.selectFork(l1.forkId);
    assertEq(l1.chainSelector, 16015286601757825753);
    assertEq(address(l1.token), 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60);
    assertEq(l1.token.balanceOf(alice), 1000e18);
    assertEq(ITypeAndVersion(address(l1.router)).typeAndVersion(), "Router 1.2.0");
    assertEq(ITypeAndVersion(l1.proxyPool).typeAndVersion(), "LockReleaseTokenPoolAndProxy 1.5.0");
    assertEq(ITypeAndVersion(address(l1.EVM2EVMOnRamp1_2)).typeAndVersion(), "EVM2EVMOnRamp 1.2.0");
    assertEq(ITypeAndVersion(address(l1.EVM2EVMOnRamp1_5)).typeAndVersion(), "EVM2EVMOnRamp 1.5.0");
    assertEq(ITypeAndVersion(address(l1.EVM2EVMOffRamp1_2)).typeAndVersion(), "EVM2EVMOffRamp 1.2.0");
    assertEq(ITypeAndVersion(address(l1.EVM2EVMOffRamp1_5)).typeAndVersion(), "EVM2EVMOffRamp 1.5.0");
    assertTrue(l1.router.isOffRamp(l2.chainSelector, address(l1.EVM2EVMOffRamp1_2)));
    assertTrue(l1.router.isOffRamp(l2.chainSelector, address(l1.EVM2EVMOffRamp1_5)));

    vm.selectFork(l2.forkId);
    assertEq(l2.chainSelector, 3478487238524512106);
    assertEq(address(l2.token), 0xb13Cfa6f8B2Eed2C37fB00fF0c1A59807C585810);
    assertEq(l2.token.balanceOf(alice), 1000e18);
    assertEq(ITypeAndVersion(address(l2.router)).typeAndVersion(), "Router 1.2.0");
    assertEq(ITypeAndVersion(l2.proxyPool).typeAndVersion(), "BurnMintTokenPoolAndProxy 1.5.0");
    assertEq(ITypeAndVersion(address(l2.EVM2EVMOnRamp1_2)).typeAndVersion(), "EVM2EVMOnRamp 1.2.0");
    assertEq(ITypeAndVersion(address(l2.EVM2EVMOnRamp1_5)).typeAndVersion(), "EVM2EVMOnRamp 1.5.0");
    assertEq(ITypeAndVersion(address(l2.EVM2EVMOffRamp1_2)).typeAndVersion(), "EVM2EVMOffRamp 1.2.0");
    assertEq(ITypeAndVersion(address(l2.EVM2EVMOffRamp1_5)).typeAndVersion(), "EVM2EVMOffRamp 1.5.0");
    assertTrue(l2.router.isOffRamp(l1.chainSelector, address(l2.EVM2EVMOffRamp1_2)));
    assertTrue(l2.router.isOffRamp(l1.chainSelector, address(l2.EVM2EVMOffRamp1_5)));

    _label();
  }

  function _generateMessage(
    address receiver,
    uint256 tokenAmountsLength
  ) internal pure returns (Client.EVM2AnyMessage memory) {
    return
      Client.EVM2AnyMessage({
        receiver: abi.encode(receiver),
        data: "",
        tokenAmounts: new Client.EVMTokenAmount[](tokenAmountsLength),
        feeToken: address(0),
        extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
      });
  }

  function _messageToEvent(
    Client.EVM2AnyMessage memory message,
    IEVM2AnyOnRamp onRamp,
    uint256 feeTokenAmount,
    address originalSender,
    bool isL1
  ) public view returns (Internal.EVM2EVMMessage memory) {
    // Slicing is only available for calldata. So we have to build a new bytes array.
    bytes memory args = new bytes(message.extraArgs.length - 4);
    for (uint256 i = 4; i < message.extraArgs.length; ++i) {
      args[i - 4] = message.extraArgs[i];
    }
    Client.EVMExtraArgsV1 memory extraArgs = abi.decode(args, (Client.EVMExtraArgsV1));
    Internal.EVM2EVMMessage memory messageEvent = Internal.EVM2EVMMessage({
      sequenceNumber: onRamp.getExpectedNextSequenceNumber(),
      feeTokenAmount: feeTokenAmount,
      sender: originalSender,
      nonce: onRamp.getSenderNonce(originalSender) + 1,
      gasLimit: extraArgs.gasLimit,
      strict: false,
      sourceChainSelector: isL1 ? l1.chainSelector : l2.chainSelector,
      receiver: abi.decode(message.receiver, (address)),
      data: message.data,
      tokenAmounts: message.tokenAmounts,
      sourceTokenData: new bytes[](message.tokenAmounts.length),
      feeToken: isL1 ? l1.router.getWrappedNative() : l2.router.getWrappedNative(),
      messageId: ""
    });

    for (uint256 i; i < message.tokenAmounts.length; ++i) {
      // change introduced in 1.5 upgrade
      messageEvent.sourceTokenData[i] = abi.encode(
        SourceTokenData({
          sourcePoolAddress: abi.encode(isL1 ? l1.proxyPool : l2.proxyPool),
          destTokenAddress: abi.encode(address(isL1 ? l2.token : l1.token)),
          extraData: "",
          destGasAmount: 90000
        })
      );
    }

    messageEvent.messageId = Internal._hash(messageEvent, isL1 ? l1.metadataHash : l2.metadataHash);
    return messageEvent;
  }

  function _generateMetadataHash(uint64 sourceChainSelector) internal view returns (bytes32) {
    uint64 destChainSelector = sourceChainSelector == l1.chainSelector ? l2.chainSelector : l1.chainSelector;
    address onRamp = address(sourceChainSelector == l1.chainSelector ? l1.EVM2EVMOnRamp1_5 : l2.EVM2EVMOnRamp1_5);
    return keccak256(abi.encode(Internal.EVM_2_EVM_MESSAGE_HASH, sourceChainSelector, destChainSelector, onRamp));
  }

  function _label() internal {
    vm.label(address(l1.tokenPool), "l1.tokenPool");
    vm.label(address(l1.token), "l1.token");
    vm.label(address(l1.router), "l1.router");
    vm.label(address(l1.proxyPool), "l1.proxyPool");
    vm.label(address(l1.EVM2EVMOnRamp1_2), "l1.EVM2EVMOnRamp1_2");
    vm.label(address(l1.EVM2EVMOnRamp1_5), "l1.EVM2EVMOnRamp1_5");
    vm.label(address(l1.EVM2EVMOffRamp1_2), "l1.EVM2EVMOffRamp1_2");
    vm.label(address(l1.EVM2EVMOffRamp1_5), "l1.EVM2EVMOffRamp1_5");

    vm.label(address(l2.tokenPool), "l2.tokenPool");
    vm.label(address(l2.token), "l2.token");
    vm.label(address(l2.router), "l2.router");
    vm.label(address(l2.proxyPool), "l2.proxyPool");
    vm.label(address(l2.EVM2EVMOnRamp1_2), "l2.EVM2EVMOnRamp1_2");
    vm.label(address(l2.EVM2EVMOnRamp1_5), "l2.EVM2EVMOnRamp1_5");
    vm.label(address(l2.EVM2EVMOffRamp1_2), "l2.EVM2EVMOffRamp1_2");
    vm.label(address(l2.EVM2EVMOffRamp1_5), "l2.EVM2EVMOffRamp1_5");
  }
}

contract ForkPoolAfterMigration is ForkBase {
  function setUp() public override {
    super.setUp();
  }

  /// @dev Tests current version of token pools do not work with legacy on-ramps post 1.5 CCIP Migration
  /// Only lockOrBurn is incompatible post migration since the new proxyPool becomes a 'wrapped' router
  /// for the existing token pool, releaseOrMint is still compatible with legacy on-ramps
  /// see more: https://github.com/smartcontractkit/ccip/blob/11c275959902783a3c4eaddbfaa5ce5f8707e01f/contracts/src/v0.8/ccip/test/legacy/TokenPoolAndProxy.t.sol#L130-L192
  function testSendViaLegacyRouterReverts() public {
    uint256 amount = 10e18;
    // generate lockOrBurn message for lockRelease token pool on L1
    Client.EVM2AnyMessage memory message = _generateMessage(alice, 1);
    message.tokenAmounts[0] = Client.EVMTokenAmount({token: address(l1.token), amount: amount});

    vm.selectFork(l1.forkId);
    uint256 feeTokenAmount = l1.router.getFee(l2.chainSelector, message);

    // validate send reverts with onRamp caller as proxyPool
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, l1.proxyPool));
    l1.router.ccipSend{value: feeTokenAmount}(l2.chainSelector, message);

    vm.selectFork(l2.forkId);
    // modify generated lockOrBurn message for burnMint tokenPool on L2
    message.tokenAmounts[0].token = address(l2.token);
    feeTokenAmount = l2.router.getFee(l1.chainSelector, message);

    // validate send reverts with onRamp caller as proxyPool
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(CallerIsNotARampOnRouter.selector, l2.proxyPool));
    l2.router.ccipSend{value: feeTokenAmount}(l1.chainSelector, message);
  }
}

contract ForkPoolBeforeMigration is ForkBase {
  event Locked(address indexed sender, uint256 amount);
  event Burned(address indexed sender, uint256 amount);
  event Released(address indexed sender, address indexed recipient, uint256 amount);
  event Minted(address indexed sender, address indexed recipient, uint256 amount);

  uint256 internal constant BLOCK_BEFORE_MIGRATION_L1 = 6673089;
  uint256 internal constant BLOCK_BEFORE_MIGRATION_L2 = 79570677;

  function setUp() public override {
    l1.forkId = vm.createFork(vm.rpcUrl("sepolia"), BLOCK_BEFORE_MIGRATION_L1);
    l2.forkId = vm.createFork(vm.rpcUrl("arb_sepolia"), BLOCK_BEFORE_MIGRATION_L2);

    vm.selectFork(l1.forkId);
    l1.tokenPool = UpgradeableLockReleaseTokenPool_Sepolia(0x7768248E1Ff75612c18324bad06bb393c1206980);
    l1.router = IRouter(l1.tokenPool.getRouter());
    l2.chainSelector = l1.tokenPool.getSupportedChains()[0];
    l1.token = l1.tokenPool.getToken();
    l1.EVM2EVMOnRamp1_2 = IEVM2AnyOnRamp(l1.router.getOnRamp(l2.chainSelector));
    l1.EVM2EVMOffRamp1_2 = IAny2EVMOffRamp(0xdb92e73d1D630B5B7aC96840c4df0c591c7Ad23E);
    vm.prank(alice);
    l1.token.approve(address(l1.router), type(uint256).max);
    deal(address(l1.token), alice, 1000e18);
    deal(alice, 1000e18);

    vm.selectFork(l2.forkId);
    l2.tokenPool = UpgradeableBurnMintTokenPool_ArbSepolia(0x3eC2b6F818B72442fc36561e9F930DD2b60957D2);
    l2.router = IRouter(l2.tokenPool.getRouter());
    l1.chainSelector = l2.tokenPool.getSupportedChains()[0];
    l2.token = l2.tokenPool.getToken();
    l2.EVM2EVMOnRamp1_2 = IEVM2AnyOnRamp(l2.router.getOnRamp(l1.chainSelector));
    l2.EVM2EVMOffRamp1_2 = IAny2EVMOffRamp(0xFf5e1c597c5DFfC896Ab8c7b9d876D513518c4b7);
    vm.prank(alice);
    l2.token.approve(address(l2.router), type(uint256).max);
    deal(address(l2.token), alice, 1000e18);
    deal(alice, 1000e18);

    vm.selectFork(l1.forkId);
    assertEq(l1.chainSelector, 16015286601757825753);
    assertEq(address(l1.token), 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60);
    assertEq(ITypeAndVersion(address(l1.router)).typeAndVersion(), "Router 1.2.0");
    assertEq(ITypeAndVersion(address(l1.EVM2EVMOnRamp1_2)).typeAndVersion(), "EVM2EVMOnRamp 1.2.0");
    assertEq(ITypeAndVersion(address(l1.EVM2EVMOffRamp1_2)).typeAndVersion(), "EVM2EVMOffRamp 1.2.0");
    assertTrue(l1.router.isOffRamp(l2.chainSelector, address(l1.EVM2EVMOffRamp1_2)));
    // assert only one off ramp is set
    IRouter.OffRamp[] memory offRamps = l1.router.getOffRamps();
    for (uint256 i; i < offRamps.length; ++i) {
      if (offRamps[i].sourceChainSelector == l2.chainSelector) {
        assertEq(address(l1.EVM2EVMOffRamp1_2), offRamps[i].offRamp);
      }
    }

    vm.selectFork(l2.forkId);
    assertEq(l2.chainSelector, 3478487238524512106);
    assertEq(address(l2.token), 0xb13Cfa6f8B2Eed2C37fB00fF0c1A59807C585810);
    assertEq(ITypeAndVersion(address(l2.router)).typeAndVersion(), "Router 1.2.0");
    assertEq(ITypeAndVersion(address(l2.EVM2EVMOnRamp1_2)).typeAndVersion(), "EVM2EVMOnRamp 1.2.0");
    assertEq(ITypeAndVersion(address(l2.EVM2EVMOffRamp1_2)).typeAndVersion(), "EVM2EVMOffRamp 1.2.0");
    assertTrue(l2.router.isOffRamp(l1.chainSelector, address(l2.EVM2EVMOffRamp1_2)));
    // assert only one off ramp is set
    offRamps = l2.router.getOffRamps();
    for (uint256 i; i < offRamps.length; ++i) {
      if (offRamps[i].sourceChainSelector == l1.chainSelector) {
        assertEq(address(l2.EVM2EVMOffRamp1_2), offRamps[i].offRamp);
      }
    }
  }

  function testSendViaRouter() public {
    uint256 amount = 10e18;
    Client.EVM2AnyMessage memory message = _generateMessage(alice, 1);
    message.tokenAmounts[0] = Client.EVMTokenAmount({token: address(l1.token), amount: amount});

    {
      vm.selectFork(l1.forkId);
      uint256 feeTokenAmount = l1.router.getFee(l2.chainSelector, message);

      vm.expectEmit();
      emit Locked(address(l1.EVM2EVMOnRamp1_2), amount);
      vm.prank(alice);
      l1.router.ccipSend{value: feeTokenAmount}(l2.chainSelector, message);
    }
    {
      vm.selectFork(l2.forkId);
      message.tokenAmounts[0].token = address(l2.token);
      uint256 feeTokenAmount = l2.router.getFee(l1.chainSelector, message);

      vm.expectEmit();
      emit Burned(address(l2.EVM2EVMOnRamp1_2), amount);
      vm.prank(alice);
      l2.router.ccipSend{value: feeTokenAmount}(l1.chainSelector, message);
    }
  }

  function testLockOrBurnVia1_2OnRamp() public {
    uint256 amount = 10e18;
    {
      vm.selectFork(l1.forkId);

      vm.expectEmit();
      emit Locked(address(l1.EVM2EVMOnRamp1_2), amount);
      vm.prank(address(l1.EVM2EVMOnRamp1_2));
      l1.tokenPool.lockOrBurn(alice, abi.encode(alice), amount, l2.chainSelector, "");
    }
    {
      vm.selectFork(l2.forkId);
      // router is responsible for transferring liquidity, so we mock router.token.transferFrom(user, tokenPool)
      deal(address(l2.token), address(l2.tokenPool), amount);

      vm.expectEmit();
      emit Burned(address(l2.EVM2EVMOnRamp1_2), amount);
      vm.prank(address(l2.EVM2EVMOnRamp1_2));
      l2.tokenPool.lockOrBurn(alice, abi.encode(alice), amount, l1.chainSelector, "");
    }
  }

  function testReleaseOrMintVia1_2OffRamp() public {
    uint256 amount = 10e18;
    {
      vm.selectFork(l1.forkId);
      uint256 balanceBefore = l1.token.balanceOf(alice);

      vm.expectEmit();
      emit Released(address(l1.EVM2EVMOffRamp1_2), alice, amount);
      vm.prank(address(l1.EVM2EVMOffRamp1_2));
      l1.tokenPool.releaseOrMint(abi.encode(alice), alice, amount, l2.chainSelector, "");

      assertEq(l1.token.balanceOf(alice), balanceBefore + amount);
    }
    {
      vm.selectFork(l2.forkId);
      uint256 balanceBefore = l2.token.balanceOf(alice);

      vm.expectEmit();
      emit Minted(address(l2.EVM2EVMOffRamp1_2), alice, amount);
      vm.prank(address(l2.EVM2EVMOffRamp1_2));
      l2.tokenPool.releaseOrMint(abi.encode(alice), alice, amount, l1.chainSelector, "");

      assertEq(l2.token.balanceOf(alice), balanceBefore + amount);
    }
  }
}
