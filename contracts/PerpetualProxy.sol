// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.8.20;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PerpetualProxy is TransparentUpgradeableProxy{
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable public TransparentUpgradeableProxy(_logic, admin_, _data) {

    }
}
