// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

abstract contract MTokenTransfers {
    function transferIn(address tokenAddress, uint256 amount) internal virtual returns (uint256);
}
