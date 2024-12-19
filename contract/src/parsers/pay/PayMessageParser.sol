// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMessageParser} from "../IMessageParser.sol";
import {console} from "forge-std/console.sol";

contract PayMessageParser is IMessageParser {
    // Should be no longer than 4 bytes or see comment about bytes4
    string constant NATIVE_TOKEN_SYMBOL = "ETH";
    uint8 constant NATIVE_TOKEN_DECIMALS = 18;

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1("0")) && byteValue <= uint8(bytes1("9"))) {
            return byteValue - uint8(bytes1("0"));
        } else if (byteValue >= uint8(bytes1("a")) && byteValue <= uint8(bytes1("f"))) {
            return 10 + byteValue - uint8(bytes1("a"));
        } else if (byteValue >= uint8(bytes1("A")) && byteValue <= uint8(bytes1("F"))) {
            return 10 + byteValue - uint8(bytes1("A"));
        }
        revert("Illegal byte in hexCharToByte");
    }

    function _stringToAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }
        return address(uint160(bytes20(addrBytes)));
    }

    // TODO: Find an audited library that does this or similar
    function utf8BytesToUintWithDecimals(bytes calldata numStr) public pure returns (uint256, uint8, uint256) {
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
        return (result, decimals, i);
    }

    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        pure
        returns (address, uint256 value, bytes memory)
    {
        bytes calldata message = content[0][messageStart:messageEnd];
        uint256 cursor = 0;

        // 42 bytes of address
        address to = _stringToAddress(string(message[cursor:cursor + 42]));
        cursor = cursor + 42;

        // next should be a space
        require(bytes1(message[cursor:cursor + 1]) == bytes1(hex"20"), "Need a space after the address");
        cursor = cursor + 1;

        uint256 amount;
        uint8 decimals;
        uint256 lengthInBytes;
        (amount, decimals, lengthInBytes) = utf8BytesToUintWithDecimals(message[cursor:]);
        cursor = cursor + lengthInBytes;

        require(bytes1(message[cursor:cursor + 1]) == bytes1(hex"20"), "Need a space after the amount");
        cursor = cursor + 1;

        // NB If you set a longer symbol than 4 bytes for NATIVE_TOKEN_SYMBOL you need to change the bytes4:
        require(
            bytes4(message[cursor:cursor + bytes(NATIVE_TOKEN_SYMBOL).length]) == bytes5(bytes(NATIVE_TOKEN_SYMBOL)),
            "Must specify correct token"
        );
        require(decimals <= NATIVE_TOKEN_DECIMALS, "Too many decimals");

        amount = amount * (10 ** (NATIVE_TOKEN_DECIMALS - decimals));
        bytes memory data;
        return (to, amount, data);
    }
}
