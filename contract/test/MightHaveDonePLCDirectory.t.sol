// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DidProofLoader} from "./DidProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {MightHaveDonePLCDirectory} from "../src/MightHaveDonePLCDirectory.sol";

contract MightHaveDonePLCDirectoryTest is Test, DidProofLoader {

    function testRegisterUpdates() public {
        MightHaveDonePLCDirectory repo = new MightHaveDonePLCDirectory();
        DidProof memory proof = _loadProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.json");
        bytes32 finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
        bytes32 did = bytes32(bytes(proof.did));

        // Output by our python script for the pubkey using eth_key when preparing the fixture
        address expectedFinalVerificationMethod = 0x96a0C856E027f207Af09BCeAe1E27D7AEA9043dB;

        address storedVerificationAddress = repo.verificationAddressAt(did, finalUpdateHash);
        assertEq(storedVerificationAddress, expectedFinalVerificationMethod, "Not expected address");
    }

    function testRegisterSplitUpdates() public {
        MightHaveDonePLCDirectory repo = new MightHaveDonePLCDirectory();

        DidProof memory proof = _loadProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.0.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
        address storedVerificationAddress = repo.verificationAddressAt(did, finalUpdateHash);
        assertNotEq(storedVerificationAddress, address(0), "Null verificationaddress");
        assertEq(finalUpdateHash, repo.uncontroversialTip(did));

        DidProof memory proof2 = _loadProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.01.json");
        bytes32 finalUpdateHash2 = sha256(proof2.ops[proof2.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof2.did)), "did changed");
        repo.registerUpdates(did, proof2.ops, proof2.sigs, proof2.pubkeys, proof2.pubkeyIndexes);
        assertNotEq(finalUpdateHash, finalUpdateHash2);
        assertEq(finalUpdateHash2, repo.uncontroversialTip(did));

        DidProof memory proof3 = _loadProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.12.json");
        bytes32 finalUpdateHash3 = sha256(proof3.ops[proof3.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof3.did)), "did changed");
        repo.registerUpdates(did, proof3.ops, proof3.sigs, proof3.pubkeys, proof3.pubkeyIndexes);
        assertNotEq(finalUpdateHash, finalUpdateHash3);
        assertNotEq(finalUpdateHash2, finalUpdateHash3);
        assertEq(finalUpdateHash3, repo.uncontroversialTip(did));
    }

    function testRegisterSplitForkingUpdates() public {
        MightHaveDonePLCDirectory repo = new MightHaveDonePLCDirectory();

        DidProof memory proof = _loadProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.common.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
        address storedVerificationAddress = repo.verificationAddressAt(did, finalUpdateHash);
        assertNotEq(storedVerificationAddress, address(0), "Null verificationaddress");
        assertEq(finalUpdateHash, repo.uncontroversialTip(did));

        DidProof memory proof2 = _loadProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.fork1.json");
        bytes32 finalUpdateHash2 = sha256(proof2.ops[proof2.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof2.did)), "did changed");
        repo.registerUpdates(did, proof2.ops, proof2.sigs, proof2.pubkeys, proof2.pubkeyIndexes);
        assertNotEq(finalUpdateHash, finalUpdateHash2);
        assertEq(finalUpdateHash2, repo.uncontroversialTip(did));

        DidProof memory proof3 = _loadProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.fork2.json");
        bytes32 finalUpdateHash3 = sha256(proof3.ops[proof3.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof3.did)), "did changed");
        repo.registerUpdates(did, proof3.ops, proof3.sigs, proof3.pubkeys, proof3.pubkeyIndexes);
        assertNotEq(finalUpdateHash, finalUpdateHash3);
        assertNotEq(finalUpdateHash2, finalUpdateHash3);

        assertEq(bytes32(0), repo.uncontroversialTip(did));
    }

    function testHomeMadeUpdates() public {
        MightHaveDonePLCDirectory repo = new MightHaveDonePLCDirectory();
        DidProof memory proof = _loadProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.json");
        bytes32 finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        bytes32 did = bytes32(bytes(proof.did));
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
    }
}
