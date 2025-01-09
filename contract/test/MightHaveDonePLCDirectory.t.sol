// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DidProofLoader} from "./DidProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {MightHaveDonePLCDirectory} from "../src/MightHaveDonePLCDirectory.sol";

contract MightHaveDonePLCDirectoryTest is Test, DidProofLoader {
    MightHaveDonePLCDirectory public repo;
    bytes32 did;
    bytes32 finalUpdateHash;

    function setUp() public {
        repo = new MightHaveDonePLCDirectory();
        DidProof memory proof = _loadProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.json");
        finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        did = bytes32(bytes(proof.did));
        repo.registerUpdates(did, proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
    }

    function testRegisterUpdates() public view {
        // Output by our python script for the pubkey using eth_key when preparing the fixture
        address expectedFinalVerificationMethod = 0x96a0C856E027f207Af09BCeAe1E27D7AEA9043dB;

        address storedVerificationAddress = repo.verificationAddressAt(did, finalUpdateHash);
        assertEq(storedVerificationAddress, expectedFinalVerificationMethod, "Not expected address");
    }

    function testUncontroversialTip() public view {
        // TODO: Make some forking updates and test it gets zeroed
        assertEq(finalUpdateHash, repo.uncontroversialTip(did), "The tip should be registered as uncontroversial");
    }
}
