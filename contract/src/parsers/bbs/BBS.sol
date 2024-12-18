// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

event LogPostMessage(address indexed sender, string message);

contract BBS {
    mapping(address => string) public messages;

    function postMessage(string memory message) external {
        messages[msg.sender] = message;
        emit LogPostMessage(msg.sender, message);
    }
}
