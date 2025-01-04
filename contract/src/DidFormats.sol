// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Base58} from "@base58-solidity/contracts/Base58.sol";

abstract contract DidFormats {

    function sha256ToBase32CID(bytes32 hash) pure public returns (string memory) {
        bytes memory b;
        return string(b);
    }

    function didKeyToBytes(string calldata key) pure public returns (bytes memory) {
        bytes memory decoded = Base58.decodeFromString(key);
        return bytes(substring(string(decoded), 2, decoded.length));
    }

    function didKeyToAddress(string calldata key) pure public returns (address) {
        return address(uint160(uint256(keccak256(didKeyToBytes(key)))));
    }

    function sigToBase64URLEncoded(bytes calldata rs) pure public returns (bytes memory) {
        return bytes(Base64.encodeURL(rs));
    }

    function substring(string memory str, uint startIndex, uint endIndex) public pure returns (string memory ) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex-startIndex);
        for(uint i = startIndex; i < endIndex; i++) {
            result[i-startIndex] = strBytes[i];
        }
        return string(result);
    }

}
