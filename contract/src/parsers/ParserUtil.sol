// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library ParserUtil {
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

    function stringToAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }
        return address(uint160(bytes20(addrBytes)));
    }

    function hexStrToBytes32(string memory str) public pure returns (bytes32) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 64, "Invalid bytes32 length");
        bytes memory bytes32Bytes = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            bytes32Bytes[i] = bytes1(hexCharToByte(strBytes[i * 2]) * 16 + hexCharToByte(strBytes[1 + i * 2]));
        }

        return bytes32(bytes32Bytes);
    }

    // The string should contain numbers (ascii 48-57) and optionally 1 decimal point (46).
    function stringStartingWithDecimalsToUint256(string calldata numStr, uint8 unitDecimals)
        public
        pure
        returns (uint256, uint256)
    {
        uint256 numBytes = bytes(numStr).length;
        uint8 decimals = 0;
        bool isPastDecimal = false;
        uint256 i;
        uint256 result;
        for (i = 0; i < numBytes; i++) {
            uint256 c = uint256(uint8(bytes1(bytes(numStr)[i])));
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
}
