// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "../../components/MainStorage.sol";



/**
 * @dev Rollup helper functions
 */
contract PerpHelpers is MainStorage {

    /**
     * @dev Load poseidon smart contract
     * @param _poseidon2Elements Poseidon contract address for 2 elements
     * @param _poseidon3Elements Poseidon contract address for 3 elements
     * @param _poseidon4Elements Poseidon contract address for 4 elements
     */
    function _initializeHelpers(
        address _poseidon2Elements,
        address _poseidon3Elements,
        address _poseidon4Elements,
        address _poseidon5Elements
    ) internal {
        _insPoseidonUnit2 = PoseidonUnit2(_poseidon2Elements);
        _insPoseidonUnit3 = PoseidonUnit3(_poseidon3Elements);
        _insPoseidonUnit4 = PoseidonUnit4(_poseidon4Elements);
        _insPoseidonUnit5 = PoseidonUnit5(_poseidon5Elements);
    }

    /**
     * @dev Hash poseidon for 2 elements
     * @param inputs Poseidon input array of 2 elements
     * @return Poseidon hash
     */
    function _hash2Elements(uint256[2] memory inputs)
        internal
        view
        returns (uint256)
    {
        return _insPoseidonUnit2.poseidon(inputs);
    }

    /**
     * @dev Hash poseidon for 3 elements
     * @param inputs Poseidon input array of 3 elements
     * @return Poseidon hash
     */
    function _hash3Elements(uint256[3] memory inputs)
        internal
        view
        returns (uint256)
    {
        return _insPoseidonUnit3.poseidon(inputs);
    }

    /**
     * @dev Hash poseidon for 4 elements
     * @param inputs Poseidon input array of 4 elements
     * @return Poseidon hash
     */
    function _hash4Elements(uint256[4] memory inputs)
        internal
        view
        returns (uint256)
    {
        return _insPoseidonUnit4.poseidon(inputs);
    }

    function _hash5Elements(uint256[5] memory inputs)
    internal
    view
    returns (uint256)
    {
        return _insPoseidonUnit5.poseidon(inputs);
    }

    /**
     * @dev Hash poseidon for sparse merkle tree nodes
     * @param left Input element array
     * @param right Input element array
     * @return Poseidon hash
     */
    function _hashNode(uint256 left, uint256 right)
        internal
        view
        returns (uint256)
    {
        uint256[2] memory inputs;
        inputs[0] = left;
        inputs[1] = right;
        return _hash2Elements(inputs);
    }

    /**
     * @dev Hash poseidon for sparse merkle tree final nodes
     * @param key Input element array
     * @param value Input element array
     * @return Poseidon hash1
     */
    function _hashFinalNode(uint256 key, uint256 value)
        internal
        view
        returns (uint256)
    {
        uint256[3] memory inputs;
        inputs[0] = key;
        inputs[1] = value;
        inputs[2] = 1;
        return _hash3Elements(inputs);
    }

    /**
     * @dev Verify sparse merkle tree proof
     * @param root Root to verify
     * @param siblings Siblings necessary to compute the merkle proof
     * @param key Key to verify
     * @param value Value to verify
     * @return True if verification is correct, false otherwise
     */
    function _smtVerifier(
        uint256 root,
        uint256[] memory siblings,
        uint256 key,
        uint256 value
    ) internal view returns (bool) {
        // Step 2: Calcuate root
        uint256 nextHash = _hashFinalNode(key, value);
        uint256 siblingTmp;
        for (int256 i = int256(siblings.length) - 1; i >= 0; i--) {
            siblingTmp = siblings[uint256(i)];
            bool leftRight = (uint8(key >> i) & 0x01) == 1;
            nextHash = leftRight
                ? _hashNode(siblingTmp, nextHash)
                : _hashNode(nextHash, siblingTmp);
        }

        // Step 3: Check root
        return root == nextHash;
    }

    /**
     * @dev Build entry for the exit tree leaf
     * @param balance Balance of the account
     * @param ay Public key babyjubjub represented as point: sign + (Ay)
     * @param ethAddress Ethereum address
     * @return uint256 array with the state variables
     */
    function _buildTreeState(
        uint256 balance,
        uint8 balanceSign,
        uint256 ay,
        address ethAddress,
        uint256 ordersRoot,
        uint256 positionsRoot
    ) internal pure returns (uint256[5] memory) {
        uint256[5] memory stateArray;

        stateArray[0] = balance;
        stateArray[0] |= (ay >> 255) << (120);
        stateArray[0] |= balanceSign << 128;
        stateArray[1] = (ay << 1) >> 1; // last bit set to 0
        stateArray[2] = uint256(ethAddress);
        stateArray[3] = ordersRoot;
        stateArray[4] = positionsRoot;

        return stateArray;
    }

    /**
     * @dev return information from specific call data info
     * @param posParam parameter number relative to 0 to extract the info
     * @return ptr ptr to the call data position where the actual data starts
     * @return len Length of the data
     */
    function _getCallData(uint256 posParam)
        internal
        pure
        returns (uint256 ptr, uint256 len)
    {
        assembly {
            let pos := add(4, mul(posParam, 32))
            ptr := add(calldataload(pos), 4)
            len := calldataload(ptr)
            ptr := add(ptr, 32)
        }
    }

    /**
     * @dev This package fills at least len zeros in memory and a maximum of len+31
     * @param ptr The position where it starts to fill zeros
     * @param len The minimum quantity of zeros it's added
     */
    function _fillZeros(uint256 ptr, uint256 len) internal pure {
        assembly {
            let ptrTo := ptr
            ptr := add(ptr, len)
            for {

            } lt(ptrTo, ptr) {
                ptrTo := add(ptrTo, 32)
            } {
                mstore(ptrTo, 0)
            }
        }
    }
}
