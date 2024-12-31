// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMessageParser} from "../IMessageParser.sol";
import {ParserUtil} from "../ParserUtil.sol";
import {console} from "forge-std/console.sol";

contract PayMessageParser is IMessageParser {
    // Should be no longer than 4 bytes or see comment about bytes4
    string constant NATIVE_TOKEN_SYMBOL = "ETH";
    uint8 constant NATIVE_TOKEN_DECIMALS = 18;

    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        pure
        returns (address, uint256 value, bytes memory)
    {
        bytes calldata message = content[0][messageStart:messageEnd];
        uint256 cursor = 0;

        // 42 bytes of address
        address to = ParserUtil.stringToAddress(string(message[cursor:cursor + 42]));
        cursor = cursor + 42;

        // next should be a space
        require(bytes1(message[cursor:cursor + 1]) == bytes1(hex"20"), "Need a space after the address");
        cursor = cursor + 1;

        uint256 amount;
        uint8 decimals;
        uint256 lengthInBytes;
        (amount, lengthInBytes) =
            ParserUtil.stringStartingWithDecimalsToUint256(string(message[cursor:]), NATIVE_TOKEN_DECIMALS);
        cursor = cursor + lengthInBytes;

        require(bytes1(message[cursor:cursor + 1]) == bytes1(hex"20"), "Need a space after the amount");
        cursor = cursor + 1;

        // NB If you set a longer symbol than 4 bytes for NATIVE_TOKEN_SYMBOL you need to change the bytes4:
        require(
            bytes4(message[cursor:cursor + bytes(NATIVE_TOKEN_SYMBOL).length]) == bytes4(bytes(NATIVE_TOKEN_SYMBOL)),
            "Must specify correct token"
        );
        require(decimals <= NATIVE_TOKEN_DECIMALS, "Too many decimals");

        bytes memory data;
        return (to, amount, data);
    }
}
