// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "../interfaces/MTokenTransfers.sol";
import "../components/MainStorage.sol";
import "../components/Pausable.sol";

abstract contract Deposits is MainStorage, MTokenTransfers, Pausable{

    event LogDeposit(
        address sender,
        address user,
        uint256 amount
    );

    function getDepositBalance(address user) external view returns (uint256 balance) {
        balance = pendingDeposits[user][depositToken];
    }

    function deposit(address user, uint256 amount) public whenNotPaused {
        require(!blacklisted[user]&&!blacklisted[msg.sender], "BLACKLIST_USER");

        if(oldUsers[user]) {
            require(amount > 0, "INVALID_AMOUNT");
        } else {
            require(amount >= 10 ** uint(depositTokenDecimals + 1), "INVALID_AMOUNT_NEW_USER");
            oldUsers[user] = true;
        }

        // Transfer the tokens to the Deposit contract.
        uint256 exactAmount = transferIn(depositToken, amount);

        // Update the balance.
        pendingDeposits[user][depositToken] += exactAmount;
        require(pendingDeposits[user][depositToken] >= exactAmount, "DEPOSIT_OVERFLOW");

        // Log event.
        emit LogDeposit(
            msg.sender,
            user,
            exactAmount
        );
    }
}
