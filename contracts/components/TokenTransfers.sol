// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "../libraries/Common.sol";
import "../interfaces/MTokenTransfers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract TokenTransfers is MTokenTransfers{
    using Addresses for address;
    using Addresses for address payable;

    /*
      Transfers funds from msg.sender to the exchange.
    */
    function transferIn(address tokenAddress, uint256 amount) internal override returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        uint256 exchangeBalanceBefore = token.balanceOf(address(this));
        bytes memory callData = abi.encodeWithSelector(
            token.transferFrom.selector,
            msg.sender,
            address(this),
            amount
        );
        tokenAddress.safeTokenContractCall(callData);
        uint256 exchangeBalanceAfter = token.balanceOf(address(this));
        require(exchangeBalanceAfter >= exchangeBalanceBefore, "OVERFLOW");
        return exchangeBalanceAfter - exchangeBalanceBefore;
    }
}
