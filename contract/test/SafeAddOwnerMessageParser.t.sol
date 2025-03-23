// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {SkeetProofLoader} from "./SkeetProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {SafeAddOwnerMessageParser} from "../src/parsers/safe/SafeAddOwnerMessageParser.sol";
import {console} from "forge-std/console.sol";
import {Safe} from "../lib/safe-contracts/contracts/Safe.sol";

import {Enum} from "../lib/safe-contracts/contracts/common/Enum.sol";

import {BBSMessageParser} from "../src/parsers/bbs/BBSMessageParser.sol";
import {BBS} from "../src/parsers/bbs/BBS.sol";

contract PayMessageParserTest is Test, SkeetProofLoader, Enum {
    Safe safeSingleton;
    SafeAddOwnerMessageParser parser;

    function setUp() public {
        parser = new SafeAddOwnerMessageParser();
        safeSingleton = new Safe();
    }

    function testActualAddKeyPost() public {
        address[] memory trustedObservers;
        SkeetGateway gateway = new SkeetGateway(address(safeSingleton), address(0), 0, trustedObservers);
        gateway.addDomain("unconsensus.com", address(this));
        gateway.addBot("addkey", "unconsensus.com", address(parser), "");

        SkeetProof memory proof = _loadProofFixture("add_key.json");
        address expectedSafe = address(
            gateway.predictSafeAddressFromDidAndSig(bytes32(bytes(proof.did)), sha256(proof.commitNode), proof.sig, 0)
        );

        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, proof.sig
        );

        address[] memory owners = new address[](2);
        owners = Safe(payable(expectedSafe)).getOwners();
        assertEq(2, owners.length, "Safe should have 2 owners now");
        assertEq(
            Safe(payable(expectedSafe)).getOwners()[0],
            address(0x4c582d321fB6A00f85C41686022709D8Eb9C28C3),
            "Newly added owner is owner 0"
        );
        assertEq(Safe(payable(expectedSafe)).getOwners()[1], address(gateway), "The SkeetGateway is owner 1");
    }

    function testApproveHashAfterAddKey() public {
        address[] memory trustedObservers;
        SkeetGateway gateway = new SkeetGateway(address(safeSingleton), address(0), 0, trustedObservers);
        gateway.addDomain("unconsensus.com", address(this));
        gateway.addBot("addkey", "unconsensus.com", address(parser), "");

        SkeetProof memory proof = _loadProofFixture("add_key.json");

        address expectedSafe = address(
            gateway.predictSafeAddressFromDidAndSig(bytes32(bytes(proof.did)), sha256(proof.commitNode), proof.sig, 0)
        );

        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, proof.sig
        );

        // Pretend the second owner increased the threshold
        vm.prank(0x4c582d321fB6A00f85C41686022709D8Eb9C28C3);

        // Want to call this but we can't call it directly
        // Safe(payable(expectedSafe)).changeThreshold(2);

        bytes memory payloadData = abi.encodeWithSignature("changeThreshold(uint256)", uint256(2));
        Safe(payable(expectedSafe)).execTransaction(
            expectedSafe,
            0,
            payloadData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            abi.encodePacked(
                bytes32(uint256(uint160(address(0x4c582d321fB6A00f85C41686022709D8Eb9C28C3)))), bytes32(0), uint8(1)
            ) // special fake signature for a contract call
        );
        assertEq(Safe(payable(expectedSafe)).getThreshold(), 2, "threshold change did not work");

        // Now we test with a bbs request

        BBS bbs; // makes 0x2e234DAe75C793f67A35089C9d99245E1C58470b
        bbs = new BBS();
        BBSMessageParser bbsParser = new BBSMessageParser(address(bbs));
        gateway.addDomain("blah.example.com", address(this));
        gateway.addBot("bbs", "blah.example.com", address(bbsParser), "");

        SkeetProof memory proof2 = _loadProofFixture("bbs_blah_example_com.json");

        assertEq(proof.did, proof2.did);
        assertEq(
            gateway.predictSignerAddressFromSig(sha256(proof.commitNode), proof.sig),
            gateway.predictSignerAddressFromSig(sha256(proof2.commitNode), proof2.sig)
        );

        address expectedSafeBBS = address(
            gateway.predictSafeAddressFromDidAndSig(
                bytes32(bytes(proof2.did)), sha256(proof2.commitNode), proof2.sig, 0
            )
        );
        assertEq(expectedSafeBBS, expectedSafe, "BBS should use the same safe as the add key");

        vm.recordLogs();
        gateway.handleSkeet(
            proof2.content, proof2.botNameLength, proof2.nodes, proof2.nodeHints, proof2.commitNode, proof2.sig
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);
        assertEq(entries[2].topics[3], bytes32(uint256(uint160(address(bbs)))), "topic 2 should be the bbs we called");
    }
}
