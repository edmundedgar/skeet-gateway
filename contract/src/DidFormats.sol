// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Base58} from "@base58-solidity/contracts/Base58.sol";
import {Base32} from "@0x00000002/ipfs-cid-solidity/contracts/Base32.sol";

import {console} from "forge-std/console.sol";

import {Secp256k1PubkeyCompression} from "./Secp256k1PubkeyCompression.sol";

abstract contract DidFormats is Secp256k1PubkeyCompression {
    function sha256ToBase32CID(bytes32 hash) public pure returns (string memory) {
        bytes memory prefix = bytes(hex"01711220");
        return Base32.encodeToString(bytes.concat(prefix, hash));
    }

    // see https://w3c-ccg.github.io/did-method-key/#bib-multibase
    function pubkeyBytesToDidKey(bytes calldata pubkey) public pure returns (string memory) {
        // e7 means secp256k1-pub - Secp256k1 public key (compressed)
        // 01 seems to be there???
        bytes memory prefix = bytes(hex"e701");
        bytes1 compressionByte = compressionByte(bytes32(pubkey[32:]));
        bytes memory encoded = Base58.encode(bytes.concat(prefix, compressionByte, pubkey[0:32]));
        return string.concat("did:key:z", string(encoded));
    }

    function genesisHashToDidKey(bytes32 genesisHash) public pure returns (string memory) {
        // e7 means secp256k1-pub - Secp256k1 public key (compressed)
        // 01 seems to be there???
        bytes memory encoded = Base58.encode(bytes.concat(genesisHash));
        return string.concat("did:key:z", string(encoded));
    }

    function sigToBase64URLEncoded(bytes calldata rs) public pure returns (bytes memory) {
        return bytes(Base64.encodeURL(rs));
    }
}
