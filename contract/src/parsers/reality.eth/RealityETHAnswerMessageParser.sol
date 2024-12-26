// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMessageParserFull} from "../IMessageParserFull.sol";
import {ParserUtil} from "../ParserUtil.sol";
import {IRealityETH} from "./IRealityETH.sol";
import {DagCborNavigator} from "../../DagCborNavigator.sol";
import {console} from "forge-std/console.sol";

contract RealityETHAnswerMessageParser is IMessageParserFull {
    // Should be no longer than 4 bytes or see comment about bytes4
    string constant NATIVE_TOKEN_SYMBOL = "ETH";
    uint8 constant NATIVE_TOKEN_DECIMALS = 18;

    address realityETH;

    // Link that will be in the question, after which we should find the question ID
    // This will limit us to the correct reality.eth and the correct chain
    string linkURLPrefix;

    constructor(address _realityETH, string memory _linkURLPrefix) {
        realityETH = _realityETH;
        // URL eg
        // https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0x<64 characters which are then truncated>"
        linkURLPrefix = _linkURLPrefix;
        require(realityETH != address(0), "missing realityETH address");
        require(bytes(linkURLPrefix).length > 0, "missing linkURLPrefix");
    }

    function parseFullMessage(bytes[] calldata content, uint256 messageStart, uint256)
        external
        returns (address, uint256 value, bytes memory)
    {
        uint256 cursor = messageStart;

        bytes32 answer;
        console.logBytes(content[0][cursor:]);
        if (bytes4(content[0][cursor:cursor + 4]) == bytes4("Yes ")) {
            answer = bytes32(uint256(1));
            cursor = cursor + 4;
        } else if (bytes3(content[0][cursor:cursor + 3]) == bytes3("No ")) {
            answer = bytes32(uint256(0));
            cursor = cursor + 3;
        } else {
            revert("Answer not recognized");
        }

        uint256 amount;
        uint256 lengthInBytes;
        (amount, lengthInBytes) =
            ParserUtil.stringStartingWithDecimalsToUint256(string(content[0][cursor:]), NATIVE_TOKEN_DECIMALS);
        cursor = cursor + lengthInBytes;

        require(bytes1(content[0][cursor:cursor + 1]) == bytes1(hex"20"), "Need a space after the amount");
        cursor = cursor + 1;

        // NB If you set a longer symbol than 4 bytes for NATIVE_TOKEN_SYMBOL you need to change the bytes4:
        require(
            bytes4(content[0][cursor:cursor + bytes(NATIVE_TOKEN_SYMBOL).length]) == bytes4(bytes(NATIVE_TOKEN_SYMBOL)),
            "Must specify correct token"
        );

        // {'text': 'Will this question show up on sepolia reality.eth?  #fe8880c...0229f78\n\n⇒Answer', '$type': 'app.bsky.feed.post', 'facets': [{'index': {'byteEnd': 81, 'byteStart': 71}, 'features': [{'uri': 'https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0xfe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78', '$type': 'app.bsky.richtext.facet#link'}]}, {'index': {'byteEnd': 70, 'byteStart': 52}, 'features': [{'tag': 'fe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78', '$type': 'app.bsky.richtext.facet#tag'}]}], 'createdAt': '2024-12-19T21:08:48.000Z'}

        // TODO: This fetches any uri
        // Maybe we should filter it by prefix in the selector

        // facets > any item > features > any item > uri
        DagCborNavigator.DagCborSelector[] memory urlSelector = new DagCborNavigator.DagCborSelector[](5);
        urlSelector[0] = DagCborNavigator.createTargetSelector("uri");
        urlSelector[1] = DagCborNavigator.createSelector();
        urlSelector[2] = DagCborNavigator.createSelector("features");
        urlSelector[3] = DagCborNavigator.createSelector();
        urlSelector[4] = DagCborNavigator.createSelector("facets");

        uint256 fieldEnd;
        (cursor, fieldEnd) = DagCborNavigator.firstMatch(content[1], urlSelector, 0, 0);
        require(cursor > 0, "uri field not found");

        require(
            keccak256(content[1][cursor:fieldEnd - 64]) == keccak256(bytes(linkURLPrefix)), "URL found in CBOR wrong"
        );

        bytes32 questionId = ParserUtil.hexStrToBytes32(string(content[1][fieldEnd - 64:fieldEnd]));
        // TODO: Check the current answer to make sure we're changing it

        bytes memory data =
            abi.encodeWithSignature("submitAnswer(bytes32,bytes32,uint256)", questionId, answer, uint256(0));

        return (realityETH, amount, data);
    }
}
