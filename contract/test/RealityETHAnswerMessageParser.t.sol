// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {SkeetProofLoader} from "./SkeetProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {RealityETH_v3_0} from "./external/RealityETH-3.0.sol";
import {RealityETHAnswerMessageParser} from "../src/parsers/reality.eth/RealityETHAnswerMessageParser.sol";
import {console} from "forge-std/console.sol";

contract RealityETHAnswerMessageParserTest is Test, SkeetProofLoader {
    RealityETHAnswerMessageParser parser;
    address realityETH;

    function setUp() public {
        address realityETHOrig = address(new RealityETH_v3_0());
        realityETH = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

        // This copies the code to the expected address but not the state
        vm.etch(realityETH, realityETHOrig.code);

        // This should have been done in the constructor
        // Doesn't matter what the template is, we just need there to be one at ID 0 (yes/no question)
        RealityETH_v3_0(realityETH).createTemplate("fake template");

        // A URL looks like:
        // https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0xfe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78
        // We trim off the final 32 bytes (64 characters) which will be replaced with a different question ID
        string memory linkURLPrefix =
            "https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0x";

        parser = new RealityETHAnswerMessageParser(realityETH, linkURLPrefix);
    }

    function testSetup() public view {
        uint256 template0Block = RealityETH_v3_0(realityETH).templates(uint256(0));
        assertTrue(template0Block > 0, "Template 0 should have been created at some block");
        uint256 template1Block = RealityETH_v3_0(realityETH).templates(uint256(1));
        assertEq(
            template1Block,
            0,
            "Template 1 does not exist in our test environment even though the real environment would have it"
        );
    }

    function testFullAnswerMessageParsing() public {
        SkeetProof memory proof = _loadProofFixture("answer_reality_eth_bot.json");
        address to;
        uint256 value;
        bytes memory data;
        (to, value, data) = parser.parseMessage(proof.content, 34, 34 + 13, bytes32(0));
        assertEq(value, 300000000000000, "value should be 0.0003 * 10^18");
        assertEq(address(realityETH), to, "Expected address found");
    }
}
