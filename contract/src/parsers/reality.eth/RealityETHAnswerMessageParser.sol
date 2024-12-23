// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMessageParser} from "../IMessageParser.sol";
import {IRealityETH} from "./IRealityETH.sol";
import {DagCborNavigator} from "../../DagCborNavigator.sol";
import {console} from "forge-std/console.sol";

contract RealityETHAnswerMessageParser is IMessageParser {
    // Should be no longer than 4 bytes or see comment about bytes4
    string constant NATIVE_TOKEN_SYMBOL = "ETH";
    uint8 constant NATIVE_TOKEN_DECIMALS = 18;

    address realityETH;

    // Link that will be in the question, after which we should find the question ID
    // This will limit us to the correct reality.eth and the correct chain
    bytes linkURLPrefix;

    function hexStrToBytes32(bytes memory str) public pure returns (bytes32) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 64, "Invalid bytes32 length");
        bytes memory bytes32Bytes = new bytes(32);

        for (uint i = 0; i < 32; i++) {
            bytes32Bytes[i] = bytes1(hexCharToByte(strBytes[i * 2]) * 16 + hexCharToByte(strBytes[1 + i * 2]));
        }

        return bytes32(bytes32Bytes);
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1('0')) && byteValue <= uint8(bytes1('9'))) {
            return byteValue - uint8(bytes1('0'));
        } else if (byteValue >= uint8(bytes1('a')) && byteValue <= uint8(bytes1('f'))) {
            return 10 + byteValue - uint8(bytes1('a'));
        } else if (byteValue >= uint8(bytes1('A')) && byteValue <= uint8(bytes1('F'))) {
            return 10 + byteValue - uint8(bytes1('A'));
        }
        revert("Invalid hex character");
    }

    constructor(address _realityETH, bytes memory _linkURLPrefix) {
        realityETH = _realityETH;
        // CBOR-encoded bytes for eg:
        // <header>"https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0x<64 characters which are then truncated>"
        linkURLPrefix = _linkURLPrefix;
        require(realityETH != address(0), "missing realityETH address");
        require(linkURLPrefix.length > 0, "missing linkURLPrefix");
    }

    // TODO: Find an audited library that does this or similar
    // TODO: Refactor out into some library, standardizing on this version (which handles decimals internally)
    function utf8BytesToUintWithDecimals(bytes calldata numStr, uint8 unitDecimals) public pure returns (uint256, uint256) {
        uint256 numBytes = numStr.length;
        uint8 decimals = 0;
        bool isPastDecimal = false;
        uint256 i;
        uint256 result;
        for (i = 0; i < numBytes; i++) {
            uint256 c = uint256(uint8(bytes1(numStr[i])));
            if (c == 46) {
                if (isPastDecimal) {
                    // there should only be 1 decimal point
                    break;
                }
                isPastDecimal = true;
                continue;
            } else if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
                if (isPastDecimal) {
                    decimals = decimals + 1;
                }
            } else {
                break;
            }
        }
        require(decimals <= unitDecimals, "Too many decimals");

        result = result * (10 ** (unitDecimals - decimals));
        return (result, i);
    }

    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
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
        (amount, lengthInBytes) = utf8BytesToUintWithDecimals(content[0][cursor:], NATIVE_TOKEN_DECIMALS);
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
        urlSelector[0] = DagCborNavigator.createSelector("uri");
        urlSelector[1] = DagCborNavigator.createSelector();
        urlSelector[2] = DagCborNavigator.createSelector("features");
        urlSelector[3] = DagCborNavigator.createSelector();
        urlSelector[4] = DagCborNavigator.createSelector("facets");

        uint256 fieldEnd;
        (cursor, fieldEnd) = DagCborNavigator.firstMatch(content[1], urlSelector, 0, 0);
        require(cursor > 0, "uri field not found");

        require(keccak256(content[1][cursor:fieldEnd-64]) == keccak256(linkURLPrefix), "URL found in CBOR wrong");

        bytes32 questionId = hexStrToBytes32(content[1][fieldEnd-64:fieldEnd]);
        // TODO: Check the current answer to make sure we're changing it

        bytes memory data = abi.encodeWithSignature(
            "submitAnswer(bytes32,bytes32,uint256)",
            questionId,
            answer,
            uint256(0)
        );

        return (realityETH, amount, data);
    }
}