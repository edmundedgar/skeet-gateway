// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DidProofLoader} from "./DidProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {DidVerifier} from "../src/DidVerifier.sol";
import {console} from "forge-std/console.sol";

contract DidVerifierTest is Test, DidProofLoader {
    DidVerifier public didVerifier;

    function setUp() public {
        didVerifier = new DidVerifier();
    }

    function testVerifyTransition() public view {
        DidProof memory proof = _loadProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.json");

        // Imagine we start by knowing this one
        // bytes32 initialSigHash = sha256(proof.ops[0]);

        // Our goal it to transition to the final one
        didVerifier.verifyDidTransition(proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes, proof.insertSigAt);
    }
}
