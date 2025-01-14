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

contract PayMessageParserTest is Test, SkeetProofLoader {
    Safe safeSingleton;
    SafeAddOwnerMessageParser parser;

    function setUp() public {
        parser = new SafeAddOwnerMessageParser();
        safeSingleton = new Safe();
    }

    function testActualAddKeyPost() public {
        SkeetGateway gateway = new SkeetGateway(address(safeSingleton));
        gateway.addDomain("unconsensus.com", address(this));
        gateway.addBot("addkey", "unconsensus.com", address(parser), "");

        SkeetProof memory proof = _loadProofFixture("add_key.json");
        address expectedSafe =
            address(gateway.predictSafeAddressFromSig(sha256(proof.commitNode), proof.sig));

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
}
