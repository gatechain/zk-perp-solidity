// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;


import "../perp/interfaces/VerifierRollupInterface.sol";
import "../perp/interfaces/VerifierWithdrawInterface.sol";

/**
 * @dev Interface poseidon hash function 2 elements
 */
contract PoseidonUnit2 {
    function poseidon(uint256[2] memory) public pure returns (uint256) {}
}

/**
 * @dev Interface poseidon hash function 3 elements
 */
contract PoseidonUnit3 {
    function poseidon(uint256[3] memory) public pure returns (uint256) {}
}

/**
 * @dev Interface poseidon hash function 4 elements
 */
contract PoseidonUnit4 {
    function poseidon(uint256[4] memory) public pure returns (uint256) {}
}

contract PoseidonUnit5 {
    function poseidon(uint256[5] memory) public pure returns (uint256) {}
}

struct VerifierRollup {
    VerifierRollupInterface verifierInterface;
    uint256 maxTx; // maximum rollup transactions in a batch: L2-tx + L1-tx transactions
    uint256 nLevels; // number of levels of the circuit
}

contract MainStorage {
    bool internal _initialized;
    bool internal _initializing;
    address _owner;
    uint256 _chainId;
    uint256 depositNonce;
    mapping(uint256 => bool) withdrawNonces;
    mapping(address => mapping(address => uint256)) pendingDeposits;
    mapping(address => mapping(address => uint256)) cancellationRequests;
    mapping(address => mapping(address => uint256)) pendingWithdrawals;
    mapping(address => uint256) public pendingWithdrawalTotal;
    mapping(address => bool) supportedTokens;
    bool internal _paused;

    address depositToken;
    uint8 depositTokenDecimals;
    PoseidonUnit2 _insPoseidonUnit2;
    PoseidonUnit3 _insPoseidonUnit3;
    PoseidonUnit4 _insPoseidonUnit4;
    PoseidonUnit5 _insPoseidonUnit5;

    // Verifiers array
    VerifierRollup[] public rollupVerifiers;

    // Withdraw verifier interface
    VerifierWithdrawInterface public withdrawVerifier;

    uint256 public genesisBlock;

    // Last batch forged
    uint32 public lastForgedBatch;

    // Each batch forged will have a correlated 'state root'
    mapping(uint32 => uint256) public stateRootMap;

    // Each batch forged will have a correlated 'exit tree' represented by the exit root
    mapping(uint32 => uint256) public exitRootsMap;

    // Each batch forged will have a correlated 'l1L2TxDataHash'
    mapping(uint32 => bytes32) public l1L2TxsDataHashMap;

    // Mapping of exit nullifiers, only allowing each withdrawal to be made once
    // rootId => (Idx => true/false)
    mapping(uint32 => mapping(uint48 => bool)) public exitNullifierMap;

    mapping(uint48 => address) public idxMap;

    bool public enableProof;

    address public operator;

    uint48 public insAccId;

    uint48 public feeAccId;

    mapping(address => bool) public oldUsers;

    mapping(address => bool) public blacklisted;

    mapping(uint32 => mapping(uint48 => uint256[])) public withdrawSerialNumbers;

    mapping(uint256 => bool) public allSerialNumbers;
}
