// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageParser {
    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        view
        returns (address, uint256 value, bytes memory);
}
