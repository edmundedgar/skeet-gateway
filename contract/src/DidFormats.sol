// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

abstract contract DidFormats {

    function base32CidToSha256(string calldata cid) pure public returns (bytes32) {
        return bytes32(0);
    }

    function didKeyToAddress(string calldata key) pure public returns (address) {
        return address(0);
    }

    function sigToBase64URLEncoded(bytes calldata rs) pure public returns (bytes memory) {
        bytes memory ret;
        return ret;
    }

}
