// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Base58} from "@base58-solidity/contracts/Base58.sol";
import {Base32} from "@0x00000002/ipfs-cid-solidity/contracts/Base32.sol";

import {console} from "forge-std/console.sol";

abstract contract DidFormats {
    function sha256ToBase32CID(bytes32 hash) public pure returns (string memory) {
        bytes memory prefix = bytes(hex"01711220");
        return Base32.encodeToString(bytes.concat(prefix, hash));
    }

    function didKeyToBytes(string calldata key) public pure returns (bytes memory) {
        bytes memory decoded = Base58.decodeFromString(key);
        return bytes(substring(string(decoded), 2, decoded.length));
    }

    function didKeyToAddress(string calldata key) public pure returns (address) {
        bytes32 hash = keccak256(didKeyToBytes(key));
        return address(uint160(uint256(hash)));
    }

    function sigToBase64URLEncoded(bytes calldata rs) public pure returns (bytes memory) {
        return bytes(Base64.encodeURL(rs));
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) public pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}
