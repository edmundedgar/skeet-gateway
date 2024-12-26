// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageParserFull {
    function parseFullMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        returns (address, uint256 value, bytes memory);
}
