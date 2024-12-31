// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMessageParser {
    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        returns (address, uint256 value, bytes memory);
}
