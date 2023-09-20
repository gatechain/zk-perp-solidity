// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "./interfaces/VerifierRollupInterface.sol";
import "./lib/PerpHelpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../components/Pausable.sol";

contract Perp is PerpHelpers, Pausable {

    // ERC20 signatures:

    // bytes4(keccak256(bytes("transfer(address,uint256)")));
    bytes4 constant _TRANSFER_SIGNATURE = 0xa9059cbb;

    // Modulus zkSNARK
    uint256 constant _RFIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    // [6 bytes] lastIdx + [6 bytes] newLastIdx  + [32 bytes] stateRoot  + [32 bytes] newStRoot  + [32 bytes] newExitRoot +
    // [_MAX_L1_TX * _L1_USER_TOTALBYTES bytes] l1TxsData + totall1L2TxsDataLength + feeIdxCoordinatorLength + [2 bytes] chainID + [4 bytes] batchNum =
    // 18546 bytes + totall1L2TxsDataLength + feeIdxCoordinatorLength

    uint256 constant _INPUT_SHA_CONSTANT_BYTES = 100;

    // Event emitted every time a batch is forged
    event ForgeBatch(uint32 indexed batchNum);

    // Event emitted when a withdrawal is done
    event WithdrawEvent(
        uint48 indexed idx,
        uint32 indexed numExitRoot
    );

    event LogDepositAccepted(
        address user,
        uint256 amount,
        uint256 chainId
    );

    event LogWithdrawPending(uint32 indexed batchNum, uint48 indexed idx, uint256[] serialNumber);
    event LogWithdrawAlready(uint32 indexed batchNum, uint48 indexed idx, uint256[] serialNumber);

    event InitializePerpEvent();

    /**
     * @dev Initializer function (equivalent to the constructor). Since we use
     * upgradeable smartcontracts the state vars have to be initialized here.
     */
    function initializePerp(
        address[] memory _verifiers,
        uint256[] memory _verifiersParams,
        address[] memory _poseidonElements
    ) internal {

        // set state variables
        _initializeVerifiers(_verifiers, _verifiersParams);

        genesisBlock = block.number;

        // initialize libs
        _initializeHelpers(
            _poseidonElements[0],
            _poseidonElements[1],
            _poseidonElements[2],
            _poseidonElements[3]
        );

        emit InitializePerpEvent();
    }

    //////////////
    // Coordinator operations
    /////////////

    function getInput(uint256 newStRoot, uint256 newExitRoot, bytes calldata l1L2TxsData, uint8 verifierIdx) external view returns (uint256){
        return _constructCircuitInput(
            newStRoot,
            newExitRoot,
            verifierIdx
        );
    }

    /**
     * @dev Forge a new batch providing the L1L2 Transactions and the proof.
     * If the proof is succesfully verified, update the current state, adding a new state and exit root.
     * In order to optimize the gas consumption the parameter `l1L2TxsData`
     * is read directly from the calldata using assembly with the instruction `calldatacopy`
     * @param newRoots [New state root,New exit root]
     * @param verifierIdx Verifier index
     * @param proof zk-snark input
     * Events: `ForgeBatch`
     */
    function forgeBatch(
        uint256[2] calldata newRoots,
        bytes calldata txsData,
        bytes calldata newOrders,
        bytes calldata newAccounts,
        uint256[] calldata serialNums,
        uint8 verifierIdx,
        uint256[8] calldata proof
    ) external virtual whenNotPaused {
        // Assure data availability from regular ethereum nodes
        // We include this line because it's easier to track the transaction data, as it will never be in an internal TX.
        // In general this makes no sense, as callling this function from another smart contract will have to pay the calldata twice.
        // But forcing, it avoids having to check.
        require(
            msg.sender == tx.origin,
            "Perp::forgeBatch: INTENAL_TX_NOT_ALLOWED"
        );

        require(msg.sender == operator, "only operator allowed");

        // calculate input
        uint256 input = _constructCircuitInput(
            newRoots[0],
            newRoots[1],
            verifierIdx
        );

        // verify proof
        require(
            rollupVerifiers[verifierIdx].verifierInterface.verifyProof(
                [proof[0], proof[1]],
                [[proof[2], proof[3]],[proof[4], proof[5]]],
                [proof[6], proof[7]],
                [input]
            ),
            "Perp::forgeBatch: INVALID_PROOF"
        );

        // update state
        lastForgedBatch++;
        createNewAccounts();
        uint sLen = serialNums.length;
        for(uint i; i < sLen; i++) {
            require(!allSerialNumbers[serialNums[i]], "repeated serial numbers");
            allSerialNumbers[serialNums[i]] = true;
        }
        acceptDeposits(lastForgedBatch, serialNums);
        stateRootMap[lastForgedBatch] = newRoots[0];
        exitRootsMap[lastForgedBatch] = newRoots[1];
        l1L2TxsDataHashMap[lastForgedBatch] = sha256(txsData);

        emit ForgeBatch(lastForgedBatch);
    }

    //////////////
    // User operations
    /////////////

    function getHash(address user, uint192 amount, uint256 babyPubKey) public view returns (uint256[5] memory, uint256){
        uint256[5] memory arrayState = _buildTreeState(
            amount,
            0,
            babyPubKey,
            user,
            0,
            0
        );
        uint256 stateHash = _hash5Elements(arrayState);
        return (arrayState, stateHash);
    }

    /**
     * @dev Withdraw to retrieve the tokens from the exit tree to the owner account
     * Before this call an exit transaction must be done
     * @param amount Amount to retrieve
     * @param babyPubKey Public key babyjubjub represented as point: sign + (Ay)
     * @param numExitRoot Batch number where the exit transaction has been done
     * @param siblings Siblings to demonstrate merkle tree proof
     * @param idx Index of the exit tree account
     * Events: `WithdrawEvent`
     */
    function withdrawMerkleProof(
        uint192 amount,
        uint256 babyPubKey,
        uint32 numExitRoot,
        uint256[] memory siblings,
        uint48 idx
    ) external whenNotPaused {
        require(!blacklisted[msg.sender], "BLACKLIST_USER");
        // build 'key' and 'value' for exit tree
        uint256[5] memory arrayState = _buildTreeState(
            amount,
            0,
            babyPubKey,
            msg.sender,
            0,
            0
        );
        uint256 stateHash = _hash5Elements(arrayState);
        // get exit root given its index depth
        uint256 exitRoot = exitRootsMap[numExitRoot];
        // check exit tree nullifier
        require(
            exitNullifierMap[numExitRoot][idx] == false,
            "Perp::withdrawMerkleProof: WITHDRAW_ALREADY_DONE"
        );
        // check sparse merkle tree proof
        require(
            _smtVerifier(exitRoot, siblings, idx, stateHash) == true,
            "Perp::withdrawMerkleProof: SMT_PROOF_INVALID"
        );

        // set nullifier
        exitNullifierMap[numExitRoot][idx] = true;

        _withdrawFunds(amount);

        emit WithdrawEvent(idx, numExitRoot);
        emit LogWithdrawAlready(numExitRoot, idx, withdrawSerialNumbers[numExitRoot][idx]);
    }

    //////////////
    // Viewers
    /////////////

    /**
     * @dev Retrieve the number of rollup verifiers
     * @return Number of verifiers
     */
    function rollupVerifiersLength() public view returns (uint256) {
        return rollupVerifiers.length;
    }

    //////////////
    // Internal/private methods
    /////////////

    /**
     * @dev Initialize verifiers
     * @param _verifiers verifiers address array
     * @param _verifiersParams encoeded maxTx and nlevels of the verifier as follows:
     * [8 bits]nLevels || [248 bits] maxTx
     */
    function _initializeVerifiers(
        address[] memory _verifiers,
        uint256[] memory _verifiersParams
    ) internal {
        uint256 vLen = _verifiers.length;
        for (uint256 i; i < vLen; i++) {
            rollupVerifiers.push(
                VerifierRollup({
                    verifierInterface: VerifierRollupInterface(_verifiers[i]),
                    maxTx: (_verifiersParams[i] << 8) >> 8,
                    nLevels: _verifiersParams[i] >> (256 - 8)
                })
            );
        }
    }

    function acceptDeposits(uint32 batchNum, uint256[] calldata serialNums) internal{
        uint256 dPtr; // Pointer to the calldata parameter data
        uint256 dLen; // Length of the calldata parameter
        uint256 ptr;
        (dPtr, dLen) = _getCallData(2);
        bytes memory txBytes;
        assembly {
            let txBytesLength := dLen
            txBytes := mload(0x40)
            mstore(0x40, add(add(txBytes, 0x40), txBytesLength))
            mstore(txBytes, txBytesLength)
            ptr := add(txBytes, 32)
            calldatacopy(ptr, dPtr, dLen)
        }
        uint256 txDataLength = 128;

        {
            uint l;
            uint48[] memory toIdxs  = new uint48[](32);
            {
                uint j;
                for (uint i; i < dLen; i+=txDataLength) {
                    uint48 fromIdx;
                    uint48 toIdx;
                    assembly {
                        fromIdx := mload(add(add(txBytes, 0x6), i))
                    }
                    {
                        uint toStart = i + 6;
                        assembly {
                            toIdx := mload(add(add(txBytes, 0x6), toStart))
                        }
                    }
                    if (fromIdx == 0 && toIdx != 0) {
                        {
                            bool found;
                            for (uint k; k < l; k++) {
                                if (toIdx == toIdxs[k]) {
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                toIdxs[l] = toIdx;
                                l++;
                            }
                        }
                        withdrawSerialNumbers[batchNum][toIdx].push(serialNums[j]);
                        j++;
                    }
                }
            }

            for (uint k; k < l; k++) {
                emit LogWithdrawPending(batchNum, toIdxs[k], withdrawSerialNumbers[batchNum][toIdxs[k]]);
            }
        }
        for (uint i; i < dLen; i+=txDataLength) {
            uint48 fromIdx;
            uint16 ct;
            uint128 amount;

            uint ctStart = i + 28;
            assembly {
                ct := mload(add(add(txBytes, 0x2), ctStart))
            }
            if (ct == 0) {
                assembly {
                    fromIdx := mload(add(add(txBytes, 0x6), i))
                }
                if (fromIdx != 0 && fromIdx != insAccId && fromIdx != feeAccId) {
                    address user = idxMap[fromIdx];
                    if (user != address(0)) {
                        uint amountStart = i + 12;
                        assembly {
                            amount := mload(add(add(txBytes, 0x10), amountStart))
                        }
                        if (amount != 0) {
                            uint _amount = amount / (10 ** (18-uint(depositTokenDecimals)));
                            require(
                                pendingDeposits[user][depositToken] >= _amount,
                                "DEPOSIT_INSUFFICIENT"
                            );

                            // Subtract accepted quantized amount.
                            pendingDeposits[user][depositToken] -= _amount;
                            emit LogDepositAccepted(
                                user,
                                _amount,
                                _chainId
                            );
                        }
                    }
                }
            }
        }
    }

    function createNewAccounts() internal {
        uint256 dPtr; // Pointer to the calldata parameter data
        uint256 dLen; // Length of the calldata parameter
        uint256 ptr;
        (dPtr, dLen) = _getCallData(4);
        bytes memory accountBytes;
        assembly {
            let accountBytesLength := dLen
            accountBytes := mload(0x40)
            mstore(0x40, add(add(accountBytes, 0x40), accountBytesLength))
            mstore(accountBytes, accountBytesLength)
            ptr := add(accountBytes, 32)
            calldatacopy(ptr, dPtr, dLen)
        }
        for (uint i; i < dLen; i+=26) {
            address tempAddress;
            uint48 idx;
            uint j = i+20;
            assembly {
                tempAddress := div(mload(add(add(accountBytes, 0x20), i)), 0x1000000000000000000000000)
                idx := mload(add(add(accountBytes, 0x6), j))
            }
            idxMap[idx] = tempAddress;
        }
    }



    /**
     * @dev Calculate the circuit input hashing all the elements
     * @param newStRoot New state root
     * @param newExitRoot New exit root
     * @param verifierIdx Verifier index
     */
    function _constructCircuitInput(
        uint256 newStRoot,
        uint256 newExitRoot,
        uint8 verifierIdx
    ) internal view returns (uint256) {
        uint256 oldStRoot = stateRootMap[lastForgedBatch];
        uint256 dPtr; // Pointer to the calldata parameter data
        uint256 dLen; // Length of the calldata parameter

        uint256 l1L2TxsDataLength = ((rollupVerifiers[verifierIdx].nLevels /
            8) *
            2 +
            116) * rollupVerifiers[verifierIdx].maxTx;

        bytes memory inputBytes;

        uint256 ptr; // Position for writing the bufftr

        assembly {
            let inputBytesLength := add(_INPUT_SHA_CONSTANT_BYTES, l1L2TxsDataLength)

            // Set inputBytes to the next free memory space
            inputBytes := mload(0x40)
            // Reserve the memory. 32 for the length , the input bytes and 32
            // extra bytes at the end for word manipulation
            mstore(0x40, add(add(inputBytes, 0x40), inputBytesLength))

            // Set the actua length of the input bytes
            mstore(inputBytes, inputBytesLength)

            // Set The Ptr at the begining of the inputPubber
            ptr := add(inputBytes, 32)

            mstore(ptr, oldStRoot)
            ptr := add(ptr, 32)

            mstore(ptr, newStRoot)
            ptr := add(ptr, 32)

            mstore(ptr, newExitRoot)
            ptr := add(ptr, 32)
        }

        // Copy the L2 TX Data from calldata
        (dPtr, dLen) = _getCallData(2);
        require(
            dLen <= l1L2TxsDataLength,
            "Perp::_constructCircuitInput: L2_TX_OVERFLOW"
        );
        assembly {
            calldatacopy(ptr, dPtr, dLen)
        }
        ptr += dLen;

        // L2 TX unused data is padded with 0 at the end
        _fillZeros(ptr, l1L2TxsDataLength - dLen);
        ptr += l1L2TxsDataLength - dLen;

        uint256 batchNum = lastForgedBatch + 1;

        // store 4 bytes of batch number at the end of the inputBytes
        assembly {
            mstore(ptr, shl(224, batchNum)) // 256 - 32 = 224
        }

        return uint256(sha256(inputBytes)) % _RFIELD;
    }

    /**
     * @dev Withdraw the funds to the msg.sender
     * @param amount Amount to retrieve
     */
    function _withdrawFunds(
        uint192 amount
    ) internal {
        _safeTransfer(depositToken, msg.sender, amount / (10 ** (18-uint(depositTokenDecimals))));
    }

    ///////////
    // helpers ERC20 functions
    ///////////

    /**
     * @dev Transfer tokens or ether from the smart contract
     * @param token Token address
     * @param to Address to recieve the tokens
     * @param value Quantity to transfer
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // address 0 is reserved for eth
        if (token == address(0)) {
            /* solhint-disable avoid-low-level-calls */
            (bool success, ) = msg.sender.call{value: value}(new bytes(0));
            require(success, "Perp::_safeTransfer: ETH_TRANSFER_FAILED");
        } else {
            /* solhint-disable avoid-low-level-calls */
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(_TRANSFER_SIGNATURE, to, value)
            );
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "Perp::_safeTransfer: ERC20_TRANSFER_FAILED"
            );
        }
    }
}
