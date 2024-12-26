// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SkeetProofLoader} from "./SkeetProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {BBSMessageParser} from "../src/parsers/bbs/BBSMessageParser.sol";
import {BBS} from "../src/parsers/bbs/BBS.sol";
import {console} from "forge-std/console.sol";

contract SkeetGatewayTest is Test, SkeetProofLoader {
    SkeetGateway public gateway;
    BBS public bbs; // makes 0x2e234DAe75C793f67A35089C9d99245E1C58470b

    function setUp() public {
        gateway = new SkeetGateway();
        bbs = new BBS();
        BBSMessageParser bbsParser = new BBSMessageParser(address(bbs));
        gateway.addDomain("blah.example.com", address(this));
        gateway.addBot("bbs", "blah.example.com", address(bbsParser), false);
    }

    function testChangeOwner() public {
        BBSMessageParser bbsParser = new BBSMessageParser(address(bbs));
        assertEq(gateway.owner(), address(this), "We own it on deploy");
        gateway.addDomain("blah2.example.com", address(bbsParser)); // We can still add the domain
        (address alice,) = makeAddrAndKey("alice");
        gateway.changeOwner(alice);
        vm.expectRevert();
        gateway.addDomain("blah3.example.com", address(bbsParser));
    }

    function testMerkleProvenRootHash() public view {
        // Given a hash of the content cbor, crawl up the tree and give me a root hash that I expect to find in the Sig Node
        // For each record we should have a hint which is either:
        // For node 0 (node at the tip containing the hash of the content in its v field):
        // - index+1 of the entry where we will find our hash in the data field
        // For other nodes (intermediate nodes):
        // - 0 for the l record
        // - index+1 for the e record where we should find our hash in the t field
        SkeetProof memory proof = _loadProofFixture("bbs_address_is_this_thing_on.json");

        // Check the value is in the node at the tip and recover the rkey
        (, string memory rkey) = gateway.merkleProvenRootHash(sha256(proof.content[0]), proof.nodes, proof.nodeHints);
        string memory full_key = string.concat("app.bsky.feed.post/", proof.rkey);
        assertEq(keccak256(abi.encode(rkey)), keccak256(abi.encode(full_key)));
    }

    function _testProvingFunctions(string memory fixtureName) internal view {
        SkeetProof memory proof = _loadProofFixture(fixtureName);

        (bytes32 rootHash,) = gateway.merkleProvenRootHash(sha256(proof.content[0]), proof.nodes, proof.nodeHints);
        gateway.assertCommitNodeContainsData(rootHash, proof.commitNode);
    }

    function testLongPValue() public view {
        _testProvingFunctions("long_p_val.json");
    }

    function testMerkleProvenHashAssortmentOfSkeets() public view {
        _testProvingFunctions("random_skeet0.json");
        _testProvingFunctions("random_skeet1.json");
        _testProvingFunctions("random_skeet2.json");
        _testProvingFunctions("random_skeet3.json");
        _testProvingFunctions("random_skeet5.json");
        _testProvingFunctions("random_skeet6.json");
        _testProvingFunctions("random_skeet7.json");
        _testProvingFunctions("random_skeet9.json");
        _testProvingFunctions("random_skeet10.json");
        _testProvingFunctions("random_skeet11.json");
        _testProvingFunctions("random_skeet12.json");
        _testProvingFunctions("random_skeet13.json");
    }

    function testAssertCommitNodeContainsData() public {
        SkeetProof memory proof = _loadProofFixture("bbs_address_is_this_thing_on.json");

        uint256 lastNode = proof.nodes.length - 1;
        bytes32 rootHash = sha256(proof.nodes[lastNode]);
        gateway.assertCommitNodeContainsData(rootHash, proof.commitNode);

        bytes32 someOtherHash = sha256(proof.nodes[lastNode - 1]);
        vm.expectRevert();
        gateway.assertCommitNodeContainsData(someOtherHash, proof.commitNode);
    }

    function testSameSigner() public {
        SkeetProof memory proof = _loadProofFixture("ask.json");
        address expectedSigner =
            gateway.predictSignerAddressFromSig(sha256(proof.commitNode), proof.v, proof.r, proof.s);
        SkeetProof memory proof2 = _loadProofFixture("answer.json");
        address expectedSigner2 =
            gateway.predictSignerAddressFromSig(sha256(proof2.commitNode), proof.v, proof2.r, proof2.s);
        assertEq(expectedSigner, expectedSigner2, "Same sender should get the same signer");
        assertEq(expectedSigner, 0x69f2163DE8accd232bE4CD84559F823CdC808525);
    }

    function testActualSkeetBBSPost() public {
        vm.recordLogs();

        SkeetProof memory proof = _loadProofFixture("bbs_blah_example_com.json");

        address expectedSigner = gateway.predictSignerAddressFromSig(sha256(proof.commitNode), 28, proof.r, proof.s);

        assertNotEq(expectedSigner, address(0), "Signer not found");
        address expectedSafe =
            address(gateway.predictSafeAddressFromSig(sha256(proof.commitNode), 28, proof.r, proof.s));
        assertEq(gateway.predictSafeAddress(expectedSigner), expectedSafe);
        assertNotEq(expectedSafe, address(0), "expected safe empty");

        assertEq(address(gateway.signerSafes(expectedSigner)), address(0), "Safe not created yet");

        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, 28, proof.r, proof.s
        );

        address createdSafe = address(gateway.signerSafes(expectedSigner));
        assertNotEq(createdSafe, address(0), "Safe now created");
        assertEq(createdSafe, expectedSafe, "Safe not expected address");

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(entries[0].topics[1], bytes32(uint256(uint160(expectedSigner))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(expectedSafe))));

        assertEq(gateway.signerSafes(expectedSigner).owner(), address(gateway));

        assertEq(bbs.messages(createdSafe), "post this my pretty");
        assertNotEq(bbs.messages(createdSafe), "oinK");
    }

    function testReplayProtection() public {
        SkeetProof memory proof = _loadProofFixture("bbs_blah_example_com.json");
        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, 28, proof.r, proof.s
        );
        vm.expectRevert();
        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, 28, proof.r, proof.s
        );
    }

    function testAddressRecovery() public {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 hash = sha256("Signed by Alice");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, hash);
        address signer = ecrecover(hash, v, r, s);
        assertEq(alice, signer);

        address expectedSigner = gateway.predictSignerAddressFromSig(hash, v, r, s);
        assertEq(expectedSigner, signer);
    }

    function testRealAddressRecovery() public pure {
        // Address for edmundedgar.unconsensus.com, recovered earlier by signing a message with the private key then running ecrecover on it
        address expect = address(0x69f2163DE8accd232bE4CD84559F823CdC808525);

        // Prepared earlier by doing:
        // bytes32 priv = // fill this from edmundedgar.unconsensus.com.sec
        // bytes32 hash = sha256("Signed by Ed");
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(priv), hash);

        // cborSansSig is the data that the PDS signs.
        // It's a CBOR representation of:
        /*
        rootRecordSansSig: {
            did: 'did:plc:mtq3e4mgt7wyjhhaniezej67',
            rev: '3laykltosp22q',
            data: CID(bafyreidg3jtflp4nu6nwtkdsthhrod7nqsl7umczg6o4jkf74hrizk25sm),
            prev: null,
            version: 3
        }
        Once it has signed it will add the signature to its rootRecord.
        We only care about the CID.
        */

        bytes memory cborSansSig =
            hex"a56364696478206469643a706c633a6d74713365346d67743777796a6868616e69657a656a3637637265766d336c61796b6c746f73703232716464617461d82a5825000171122066da6655bf8da79b69a87299cf170fed8497fa3059379dc4a8bfe1e28cab5d936470726576f66776657273696f6e03";
        bytes32 hash = sha256(cborSansSig);

        // sig from car file was 'd395a8c48c851c0ae8abe772d9fc33cac0619709ca2bcc5b60f7ff9e6ff7bf8363f68f57c10e0277403e800c5b9fd7c448f9816bf4ab878fd8148ceb24ef520b',
        // manually split it in half
        bytes32 r = 0xd395a8c48c851c0ae8abe772d9fc33cac0619709ca2bcc5b60f7ff9e6ff7bf83;
        bytes32 s = 0x63f68f57c10e0277403e800c5b9fd7c448f9816bf4ab878fd8148ceb24ef520b;

        uint8 v = 28;
        // bool found = false;
        // for(uint8 v=0; v<255; v++) { } // Earlier we had to try all possible v values to find the one they used
        address signer = ecrecover(hash, v, r, s);
        assertEq(expect, signer, "should recover the same signer");
    }
}
