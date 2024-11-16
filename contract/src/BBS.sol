// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract BBS {

    mapping(address => string) public messages;

    function postMessage(string memory message) external {
        messages[msg.sender] = message;
    }

}
