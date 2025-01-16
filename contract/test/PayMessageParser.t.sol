// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {SkeetProofLoader} from "./SkeetProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {PayMessageParser} from "../src/parsers/pay/PayMessageParser.sol";
import {BBS} from "../src/parsers/bbs/BBS.sol";
import {console} from "forge-std/console.sol";
import {Safe} from "../lib/safe-contracts/contracts/Safe.sol";

contract PayMessageParserTest is Test, SkeetProofLoader {
    PayMessageParser parser;
    Safe safeSingleton;

    function setUp() public {
        parser = new PayMessageParser();
        safeSingleton = new Safe();
    }

    function testFullMessageParsing() external view {
        SkeetProof memory proof = _loadProofFixture("pay_unconsensus_com.json");
        address to;
        uint256 value;
        bytes memory data;
        (to, value, data) = parser.parseMessage(proof.content, 29, 141, address(0));
        assertEq(value, 12300000000000000, "value should be 0.0123 * 10^18");
        assertEq(address(0xB6aaa1DAd9D09d689dc6111dcc6EA2A0d641b406), to, "Expected address found");
    }

    function testActualSkeetPayPost() public {
        SkeetGateway gateway = new SkeetGateway(address(safeSingleton));
        gateway.addDomain("unconsensus.com", address(this));
        gateway.addBot("pay", "unconsensus.com", address(parser), "");

        SkeetProof memory proof = _loadProofFixture("pay_unconsensus_com.json");
        address expectedSafe = address(
            gateway.predictSafeAddressFromDidAndSig(bytes32(bytes(proof.did)), sha256(proof.commitNode), proof.sig, 0)
        );
        vm.deal(expectedSafe, 1 ether);
        assertEq(address(expectedSafe).balance, 1000000000000000000);

        assertEq(address(0xB6aaa1DAd9D09d689dc6111dcc6EA2A0d641b406).balance, 0);

        gateway.handleSkeet(
            proof.content, proof.botNameLength, proof.nodes, proof.nodeHints, proof.commitNode, proof.sig
        );

        assertEq(address(0xB6aaa1DAd9D09d689dc6111dcc6EA2A0d641b406).balance, 12300000000000000);
        assertEq(address(expectedSafe).balance, 1000000000000000000 - 12300000000000000);
    }
}
