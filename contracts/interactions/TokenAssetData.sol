// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.8.20;

import "../components/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenAssetData is Ownable{
    event LogTokenSet(address user, address token);

    function setDepositToken(address _depositToken) external onlyOwner {
        depositTokenDecimals = ERC20(_depositToken).decimals();
        require(depositTokenDecimals <= 18, "decimals gt 18");
        depositToken = _depositToken;
        emit LogTokenSet(msg.sender, _depositToken);
    }

    function getDepositToken() external view returns (address){
        return depositToken;
    }
}
