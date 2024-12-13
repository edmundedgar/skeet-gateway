// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMessageParser {
    function parseMessage(bytes calldata message) external view returns (address, uint256 value, bytes memory);
}
