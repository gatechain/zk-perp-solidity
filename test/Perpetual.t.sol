// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {Test, console2} from "forge-std/Test.sol";
import {Perpetual} from "../contracts/Perpetual.sol";
import {VerifierRollupHelper} from "../contracts/perp/test/VerifierRollupHelper.sol";
import {PoseidonUnit2, PoseidonUnit3, PoseidonUnit4, PoseidonUnit5} from "../contracts/components/MainStorage.sol";
import {Poseidon} from "./perp/helpers/Poseidon.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract PerpetualTest is Test {
    Perpetual public perpetual;
    PoseidonUnit3 p3;
    ERC20PresetMinterPauser depositToken;
    VerifierRollupHelper verifier;
    address[] verifiers;
    uint256[] verifiersParams;
    address[] poseidonElements;
    address owner = address(1);
    address operator = address(2);
    address alice = address(3);
    address bob = address(4);
    uint nLevel = 48;
    uint maxTx = 8;
    uint48 feeAccId = 100;
    uint48 insAccId = 101;
    function setUp() public {
        perpetual = new Perpetual();
        Poseidon p = new Poseidon();
        PoseidonUnit2 p2 = new PoseidonUnit2();
        vm.etch(address(p2), p.poseidon2());
        p3 = new PoseidonUnit3();
        vm.etch(address(p3), p.poseidon3());
        PoseidonUnit4 p4 = new PoseidonUnit4();
        vm.etch(address(p4), p.poseidon4());
        PoseidonUnit5 p5 = new PoseidonUnit5();
        vm.etch(address(p5), p.poseidon5());
        verifier = new VerifierRollupHelper();
        depositToken = new ERC20PresetMinterPauser("TEST", "TEST");
        depositToken.mint(alice, 100 ether);
        verifiers = new address[](1);
        verifiers[0] = address(verifier);
        verifiersParams = new uint256[](1);
        verifiersParams[0] = (nLevel<<248) + maxTx;
        poseidonElements = new address[](4);
        poseidonElements[0] = address(p2);
        poseidonElements[1] = address(p3);
        poseidonElements[2] = address(p4);
        poseidonElements[3] = address(p5);
    }

    function testPerpetual() public {
        perpetual.init(owner, address(depositToken), verifiers, verifiersParams, poseidonElements);
        vm.startPrank(owner);
        perpetual.setOperator(operator);
        perpetual.setFeeAccId(feeAccId);
        perpetual.setInsAccId(insAccId);
        vm.expectRevert("already set");
        perpetual.setOperator(operator);
        perpetual.updateVerifier(0, address(0), maxTx, nLevel);
        vm.expectRevert("equal id");
        perpetual.setFeeAccId(feeAccId);
        vm.expectRevert("equal id");
        perpetual.setInsAccId(insAccId);
        vm.stopPrank();
    }

    function testDeposit() public {
        perpetual.init(owner, address(depositToken), verifiers, verifiersParams, poseidonElements);
        vm.prank(owner);
        perpetual.blacklist(alice);
        vm.startPrank(alice);
        depositToken.approve(address(perpetual), 100 ether);
        vm.expectRevert("BLACKLIST_USER");
        perpetual.deposit(alice, 10 ether);
        vm.stopPrank();
        vm.prank(owner);
        perpetual.unBlacklist(alice);
        vm.startPrank(alice);
        vm.expectRevert("INVALID_AMOUNT_NEW_USER");
        perpetual.deposit(alice, 9 ether);
        perpetual.deposit(alice, 10 ether);
        assertEq(perpetual.getDepositBalance(alice), 10 ether);
        vm.expectRevert("INVALID_AMOUNT");
        perpetual.deposit(alice, 0 ether);
        vm.stopPrank();
    }

    function testPause() public {
        perpetual.init(owner, address(depositToken), verifiers, verifiersParams, poseidonElements);
        vm.prank(owner);
        perpetual.pause();
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        perpetual.deposit(alice, 1);
        vm.prank(owner);
        perpetual.unpause();
    }

    function testOwnable() public {
        perpetual.init(owner, address(depositToken), verifiers, verifiersParams, poseidonElements);
        assertEq(perpetual.owner(), owner);
        vm.expectRevert("Ownable: caller is not the owner");
        perpetual.transferOwnership(bob);
        vm.startPrank(owner);
        vm.expectRevert("Ownable: new owner is the zero address");
        perpetual.transferOwnership(address(0));
        perpetual.transferOwnership(bob);
        vm.stopPrank();
        vm.prank(bob);
        perpetual.renounceOwnership();
        assertEq(perpetual.owner(), address(0));
    }

    uint256 newStateRoot = 2137419751478705068521906425755008873135853678311800712017285884989420056126;
    uint256 newExitRoot = 10019985808056556367358710834844216557808256506073418225505036059535153726669;
    uint256[2] newRoots = [newStateRoot, newExitRoot];
    // deposit 10 withdraw 1
    bytes l1l2TxData = hex'0000000000010000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
    // deposit 11 ether withdraw 1
    bytes l1l2TxDataInvalid = hex'00000000000100000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
    bytes newOrders;
    bytes newAccountsData = hex'0000000000000000000000000000000000000003000000000001';
    uint256[] repeatSerialNums = new uint256[](2);
    uint256[] serialNums = new uint256[](1);
    uint256[8] proof = [uint256(0),0,0,0,0,0,0,0];
    uint8 verifierIdx;

    uint192 amount = 1;
    uint256 aliceBabyPubKey = 71518274403314255847822263721828525103471289019462150568854180202794041422788;
    uint32 numExitRoot = 1;
    uint256[] siblings;
    uint48 aliceIdx = 1;

    function testForgeBatch() public {
        perpetual.init(owner, address(depositToken), verifiers, verifiersParams, poseidonElements);
        vm.startPrank(owner);
        perpetual.setOperator(operator);
        perpetual.setFeeAccId(feeAccId);
        perpetual.setInsAccId(insAccId);
        vm.stopPrank();
        vm.startPrank(alice);
        depositToken.approve(address(perpetual), 10 ether);
        perpetual.deposit(alice, 10 ether);
        vm.stopPrank();
        // forgeBatch
        repeatSerialNums[0] = 1;
        repeatSerialNums[1] = 1;
        serialNums[0] = 1;
        verifierIdx = uint8(perpetual.rollupVerifiersLength()-1);
        assertEq(verifier.verifyProof(
                [proof[0], proof[1]],
                [[proof[2], proof[3]],[proof[4], proof[5]]],
                [proof[6], proof[7]],
                [perpetual.getInput(newStateRoot, newExitRoot, l1l2TxData, verifierIdx)]
            ), true);
        vm.expectRevert("Perp::forgeBatch: INTENAL_TX_NOT_ALLOWED");
        perpetual.forgeBatch(newRoots, l1l2TxData, newOrders, newAccountsData, serialNums, verifierIdx, proof);
        vm.prank(alice, alice);
        vm.expectRevert("only operator allowed");
        perpetual.forgeBatch(newRoots, l1l2TxData, newOrders, newAccountsData, serialNums, verifierIdx, proof);
        vm.startPrank(operator, operator);
        vm.expectRevert("repeated serial numbers");
        perpetual.forgeBatch(newRoots, l1l2TxData, newOrders, newAccountsData, repeatSerialNums, verifierIdx, proof);
        vm.expectRevert("DEPOSIT_INSUFFICIENT");
        perpetual.forgeBatch(newRoots, l1l2TxDataInvalid, newOrders, newAccountsData, serialNums, verifierIdx, proof);
        perpetual.forgeBatch(newRoots, l1l2TxData, newOrders, newAccountsData, serialNums, verifierIdx, proof);
        vm.stopPrank();
        // withdraw
        (, uint256 stateHash) = perpetual.getHash(alice, amount, aliceBabyPubKey);
        assertEq(p3.poseidon([aliceIdx, stateHash, 1]), newExitRoot);
        vm.prank(owner);
        perpetual.blacklist(bob);
        vm.prank(bob);
        vm.expectRevert("BLACKLIST_USER");
        perpetual.withdrawMerkleProof(amount, aliceBabyPubKey, numExitRoot, siblings, aliceIdx);
        vm.startPrank(alice);
        vm.expectRevert("Perp::withdrawMerkleProof: SMT_PROOF_INVALID");
        perpetual.withdrawMerkleProof(amount+1, aliceBabyPubKey, numExitRoot, siblings, aliceIdx);
        perpetual.withdrawMerkleProof(amount, aliceBabyPubKey, numExitRoot, siblings, aliceIdx);
        vm.expectRevert("Perp::withdrawMerkleProof: WITHDRAW_ALREADY_DONE");
        perpetual.withdrawMerkleProof(amount, aliceBabyPubKey, numExitRoot, siblings, aliceIdx);
        vm.stopPrank();
    }

    function testVerify() public {
        perpetual.init(owner, address(depositToken), verifiers, verifiersParams, poseidonElements);
        assertEq(perpetual.verify(83000000000000000000, 65914473076166773187763498024882820152744512323569416780780461998818175715642, address(0x15508B244063A73023457f40E49C2D74f6C189C3), siblings, 20000000002, 18994979598835189128588978481174813347634447981270927309133007944837855604324), true);
        assertEq(perpetual.verify(11000000000000000000, 65914473076166773187763498024882820152744512323569416780780461998818175715642, address(0x15508B244063A73023457f40E49C2D74f6C189C3), siblings, 20000000002, 16591557282143782376867310077493361343271308788799248003991693266149086039637), true);
        assertEq(perpetual.verify(10000000000000000000, 65914473076166773187763498024882820152744512323569416780780461998818175715642, address(0x15508B244063A73023457f40E49C2D74f6C189C3), siblings, 20000000002, 18953134286622285017230066067024598966357906348856717711071271111662581585443), true);
        assertEq(perpetual.verify(50000000000000000000, 65914473076166773187763498024882820152744512323569416780780461998818175715642, address(0x15508B244063A73023457f40E49C2D74f6C189C3), siblings, 20000000002, 1788225789126608248680417454704192462176023290476507732267253448407450818256), true);
    }
}
