// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageParser {
    function parseMessage(bytes calldata message) external returns (address, uint256 value, bytes memory);
}
