// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DidProofLoader} from "./DidProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {ShadowDIDPLCDirectory} from "../src/ShadowDIDPLCDirectory.sol";

contract ShadowDIDPLCDirectoryTest is Test, DidProofLoader {
    address[] trustedObservers;

    function testRegisterUpdates() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();
        DidProof memory proof = _loadDidProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.json");
        bytes32 finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
        bytes32 did = bytes32(bytes(proof.did));

        // Output by our python script for the pubkey using eth_key when preparing the fixture
        address expectedFinalVerificationMethod = 0x96a0C856E027f207Af09BCeAe1E27D7AEA9043dB;

        address storedVerificationAddress = repo.verificationAddressAt(did, finalUpdateHash);
        assertEq(storedVerificationAddress, expectedFinalVerificationMethod, "Not expected address");
    }

    function testRegisterSplitUpdates() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();

        DidProof memory proof = _loadDidProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.0.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 finalUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
        address storedVerificationAddress = repo.verificationAddressAt(did, finalUpdateHash);
        assertNotEq(storedVerificationAddress, address(0), "Null verificationaddress");
        assertEq(finalUpdateHash, repo.uncontroversialTip(did));

        DidProof memory proof2 = _loadDidProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.01.json");
        bytes32 finalUpdateHash2 = sha256(proof2.ops[proof2.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof2.did)), "did changed");
        repo.registerUpdates(did, proof2.ops, proof2.sigs, proof2.pubkeys, proof2.pubkeyIndexes);
        assertNotEq(finalUpdateHash, finalUpdateHash2);
        assertEq(finalUpdateHash2, repo.uncontroversialTip(did));

        DidProof memory proof3 = _loadDidProofFixture("did:plc:pyzlzqt6b2nyrha7smfry6rv.12.json");
        bytes32 finalUpdateHash3 = sha256(proof3.ops[proof3.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof3.did)), "did changed");
        repo.registerUpdates(did, proof3.ops, proof3.sigs, proof3.pubkeys, proof3.pubkeyIndexes);
        assertNotEq(finalUpdateHash, finalUpdateHash3);
        assertNotEq(finalUpdateHash2, finalUpdateHash3);
        assertEq(finalUpdateHash3, repo.uncontroversialTip(did));
    }

    function testRegisterSplitForkingUpdates() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();

        DidProof memory proof = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.common.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 forkUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
        address storedVerificationAddress = repo.verificationAddressAt(did, forkUpdateHash);
        assertNotEq(storedVerificationAddress, address(0), "Null verificationaddress");
        assertEq(forkUpdateHash, repo.uncontroversialTip(did));

        bytes32 earlyForkHash = sha256(proof.ops[proof.ops.length - 2]);
        assertFalse(repo.isBranchForkedSince(did, earlyForkHash, forkUpdateHash));

        DidProof memory proof2 = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.fork1.json");
        bytes32 finalUpdateHash2 = sha256(proof2.ops[proof2.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof2.did)), "did changed");
        repo.registerUpdates(did, proof2.ops, proof2.sigs, proof2.pubkeys, proof2.pubkeyIndexes);
        assertNotEq(forkUpdateHash, finalUpdateHash2);
        assertEq(finalUpdateHash2, repo.uncontroversialTip(did));

        DidProof memory proof3 = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.fork2.json");
        bytes32 finalUpdateHash3 = sha256(proof3.ops[proof3.ops.length - 1]);
        assertEq(did, bytes32(bytes(proof3.did)), "did changed");
        repo.registerUpdates(did, proof3.ops, proof3.sigs, proof3.pubkeys, proof3.pubkeyIndexes);
        assertNotEq(forkUpdateHash, finalUpdateHash3);
        assertNotEq(finalUpdateHash2, finalUpdateHash3);

        assertEq(bytes32(0), repo.uncontroversialTip(did));

        assertFalse(repo.isForkedAt(did, earlyForkHash));
        assertTrue(repo.isForkedAt(did, forkUpdateHash));
        assertFalse(repo.isForkedAt(did, finalUpdateHash2));
        assertFalse(repo.isForkedAt(did, finalUpdateHash3));

        bytes32 slightlyLessEarlyForkHash = sha256(proof.ops[proof.ops.length - 1]);
        assertTrue(repo.isBranchForkedSince(did, slightlyLessEarlyForkHash, finalUpdateHash2));
        assertTrue(repo.isBranchForkedSince(did, earlyForkHash, slightlyLessEarlyForkHash));

        bytes32 postForkHash = sha256(proof3.ops[proof3.ops.length - 2]);
        assertFalse(repo.isBranchForkedSince(did, postForkHash, finalUpdateHash3));
    }

    function testUpdateBlessing() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();

        DidProof memory proof = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.common.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 forkUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);

        address[] memory noTrustedObservers;
        trustedObservers.push(address(this));

        assertTrue(
            repo.isUpdateConfirmedValid(did, forkUpdateHash, 0, noTrustedObservers),
            "unforked chain valid without minChallengeSecs requirement"
        );
        assertFalse(
            repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, noTrustedObservers),
            "unforked chain invalid with minChallengeSecs"
        );
        assertFalse(
            repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, trustedObservers),
            "unforked chain invalid with minChallengeSecs before blessing"
        );

        repo.blessUpdate(did, forkUpdateHash);
        assertFalse(
            repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, noTrustedObservers),
            "other user blessing doesn't help"
        );
        assertTrue(repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, trustedObservers), "valid once blessed");

        vm.warp(block.timestamp + 100);
        assertTrue(repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, noTrustedObservers), "valid once time past");
        assertTrue(repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, trustedObservers), "valiid for both reasons");
    }

    function testForkingUpdateBlessing() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();

        address[] memory noTrustedObservers;
        trustedObservers.push(address(this));

        DidProof memory proof = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.common.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 forkUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);

        DidProof memory proof2 = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.fork1.json");
        bytes32 finalUpdateHash2 = sha256(proof2.ops[proof2.ops.length - 1]);
        repo.registerUpdates(did, proof2.ops, proof2.sigs, proof2.pubkeys, proof2.pubkeyIndexes);

        DidProof memory proof3 = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.fork2.json");
        bytes32 finalUpdateHash3 = sha256(proof3.ops[proof3.ops.length - 1]);
        repo.registerUpdates(did, proof3.ops, proof3.sigs, proof3.pubkeys, proof3.pubkeyIndexes);

        vm.warp(block.timestamp + 50);

        assertFalse(
            repo.isUpdateConfirmedValid(did, finalUpdateHash2, 100, trustedObservers),
            "fork so should be invalid until blessed"
        );
        repo.blessUpdate(did, forkUpdateHash);
        assertTrue(
            repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, trustedObservers),
            "blessing the fork update validates the fork "
        );
        assertFalse(
            repo.isUpdateConfirmedValid(did, finalUpdateHash2, 100, trustedObservers),
            "blessing the fork update doesn't help with the tip"
        );

        repo.blessUpdate(did, finalUpdateHash2);
        assertTrue(
            repo.isUpdateConfirmedValid(did, finalUpdateHash2, 100, trustedObservers), "blessing the tip makes it valid"
        );
        assertFalse(
            repo.isUpdateConfirmedValid(did, finalUpdateHash3, 100, trustedObservers),
            "the unblessed fork is still invalid"
        );

        assertFalse(
            repo.isUpdateConfirmedValid(did, finalUpdateHash2, 100, noTrustedObservers), "fork so should be invalid"
        );
    }

    function testForkingTipVerification() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();

        DidProof memory proof = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.common.json");
        bytes32 did = bytes32(bytes(proof.did));
        bytes32 forkUpdateHash = sha256(proof.ops[proof.ops.length - 1]);
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);

        vm.warp(block.timestamp + 100);
        bytes32 preForkUpdateHash = sha256(proof.ops[proof.ops.length - 2]);

        trustedObservers.push(address(this));

        repo.blessUpdate(did, preForkUpdateHash);
        assertTrue(repo.isUpdateConfirmedValid(did, preForkUpdateHash, 100, trustedObservers), "valid once blessed");
        assertTrue(
            repo.isUpdateConfirmedValid(did, forkUpdateHash, 100, trustedObservers), "tip valid once ancestor blessed"
        );

        assertFalse(
            repo.isUpdateConfirmedValidTip(did, preForkUpdateHash, 100, trustedObservers),
            "non-tip not considered valid tip"
        );
        assertTrue(repo.isUpdateConfirmedValidTip(did, forkUpdateHash, 100, trustedObservers), "tip is valid tip");
    }

    function testHomeMadeUpdates() public {
        ShadowDIDPLCDirectory repo = new ShadowDIDPLCDirectory();
        DidProof memory proof = _loadDidProofFixture("did:plc:ee7kjipyhx3cf6nmh2l5scbl.json");
        repo.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);
    }
}
