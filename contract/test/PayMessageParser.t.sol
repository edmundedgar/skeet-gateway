// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SkeetProofLoader} from "./SkeetProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {PayMessageParser} from "../src/parsers/pay/PayMessageParser.sol";
import {BBS} from "../src/parsers/bbs/BBS.sol";
import {console} from "forge-std/console.sol";

contract PayMessageParserTest is Test, SkeetProofLoader {
    PayMessageParser parser;

    function setUp() public {
        parser = new PayMessageParser();
    }

    function testFullMessageParsing() external view {
        SkeetProof memory proof = _loadProofFixture("pay_unconsensus_com.json");
        address to;
        uint256 value;
        bytes memory data;
        (to, value, data) = parser.parseMessage(proof.content, 29, 141);
        assertEq(value, 12300000000000000, "value should be 0.0123 * 10^18");
        assertEq(address(0xB6aaa1DAd9D09d689dc6111dcc6EA2A0d641b406), to, "Expected address found");
    }

    function testActualSkeetPayPost() public {
        SkeetGateway gateway = new SkeetGateway();
        gateway.addDomain("unconsensus.com", address(this));
        gateway.addBot("pay", "unconsensus.com", address(parser));

        SkeetProof memory proof = _loadProofFixture("pay_unconsensus_com.json");
        address expectedSafe =
            address(gateway.predictSafeAddressFromSig(sha256(proof.commitNode), 28, proof.r, proof.s));
        vm.deal(expectedSafe, 1 ether);
        assertEq(address(expectedSafe).balance, 1000000000000000000);

        assertEq(address(0xB6aaa1DAd9D09d689dc6111dcc6EA2A0d641b406).balance, 0);

        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, 28, proof.r, proof.s
        );

        assertEq(address(0xB6aaa1DAd9D09d689dc6111dcc6EA2A0d641b406).balance, 12300000000000000);
        assertEq(address(expectedSafe).balance, 1000000000000000000 - 12300000000000000);
    }
}
