// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract SignerSafe {

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function executeOwnerCall(address to, uint256 value, bytes memory data) external {
        require(msg.sender == owner, "I can only be controlled by the SkeetGateway that created me");
        executeCall(to, value, data);
    }

    // Copied from Gnosis Safe
    // Ultimately this contract will probably be replaced by a Gnosis Safe
    function executeCall(address to, uint256 value, bytes memory data) internal returns (bool success) {
        assembly {
            success := call(not(0), to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

}
