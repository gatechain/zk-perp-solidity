// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./components/TokenTransfers.sol";
import "./interactions/Deposits.sol";
import "./interactions/TokenAssetData.sol";
import "./components/Initializable.sol";
import "./components/Ownable.sol";
import "./components/Pausable.sol";
import "./perp/Perp.sol";

contract Perpetual is Initializable, Ownable, Pausable, TokenTransfers, Deposits, TokenAssetData, Perp{

    event NewOperator(address indexed newOperator);
    event NewVerifier(uint indexed idx, address indexed verifier, uint maxTx, uint nLevels);
    event NewInsAccId(uint48 _insAccId);
    event NewFeeAccId(uint48 _feeAccId);
    event Blacklisted(address indexed _account);
    event UnBlacklisted(address indexed _account);

    function init(address _owner, address _depositToken,
        address[] memory _verifiers,
        uint256[] memory _verifiersParams,
        address[] memory _poseidonElements
    ) external initializer {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        _chainId = chainId;
        _transferOwnership(_owner);

        depositTokenDecimals = ERC20(_depositToken).decimals();
        require(depositTokenDecimals <= 18, "decimals gt 18");
        depositToken = _depositToken;

        initializePerp(_verifiers, _verifiersParams, _poseidonElements);
    }

    function initPerp(address[] memory _verifiers,
        uint256[] memory _verifiersParams,
        address[] memory _poseidonElements) external onlyOwner {
        initializePerp(_verifiers, _verifiersParams, _poseidonElements);
    }

    function setOperator(address _operator) external onlyOwner {
        require(operator != _operator, "already set");
        operator = _operator;
        emit NewOperator(_operator);
    }

    function updateVerifier(uint idx, address verifier, uint maxTx, uint nLevels) external onlyOwner {
        rollupVerifiers[idx] = VerifierRollup({
        verifierInterface: VerifierRollupInterface(verifier),
        maxTx: maxTx,
        nLevels: nLevels
        });
        emit NewVerifier(idx, verifier, maxTx, nLevels);
    }

    function setInsAccId(uint48 _insAccId) external onlyOwner {
        require(insAccId != _insAccId, "equal id");
        insAccId = _insAccId;
        emit NewInsAccId(_insAccId);
    }

    function setFeeAccId(uint48 _feeAccId) external onlyOwner {
        require(feeAccId != _feeAccId, "equal id");
        feeAccId = _feeAccId;
        emit NewFeeAccId(_feeAccId);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function blacklist(address _account) external onlyOwner {
        blacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    function unBlacklist(address _account) external onlyOwner {
        blacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }
}
