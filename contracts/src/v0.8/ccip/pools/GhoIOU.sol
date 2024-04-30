// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ITypeAndVersion} from "../../shared/interfaces/ITypeAndVersion.sol";
import {ILiquidityContainer} from "../../rebalancer/interfaces/ILiquidityContainer.sol";

import {TokenPool} from "./TokenPool.sol";
import {RateLimiter} from "../libraries/RateLimiter.sol";

import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

import {console2} from "forge-std/console2.sol";

contract GhoIOU { // TODO: Upgradeable
  mapping(address => uint256) pendingBalance;

  function setPendingBalance(address user, uint256 amount) public {
    // TODO: onlyOwner
    pendingBalance[user] = amount;

    // TODO: event
  }

  function getPendingBalance(address user) public view returns (uint256) {
    return pendingBalance[user];
  }

  function sendIOU() public {
    // TODO: Send arbitrary message to destination TokenPool
    // This must pay with feeToken (native or LINK for now)
    // TODO: check supported network
  }
}
