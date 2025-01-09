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

    // see https://github.com/did-method-plc/did-method-plc?tab=readme-ov-file#operation-serialization-signing-and-validation
    function genesisHashToDidKey(bytes32 signedGenesisHash) public pure returns (bytes32) {
        // In pseudo-code: did:plc:${base32Encode(sha256(createOp)).slice(0,24)}

        bytes memory did = new bytes(32);

        bytes memory didPrefix = bytes(string.concat("did:plc:"));
        for (uint256 i = 0; i < 8; i++) {
            did[i] = didPrefix[i];
        }

        // This will prepend a spurious "b" to the start for some multihash reason
        bytes memory didSuffix = Base32.encode(bytes.concat(signedGenesisHash));

        for (uint256 i = 0; i < 24; i++) {
            // did starts at index 8 after did:plc:
            // suffix starts at index 1 after the spurious b
            did[8 + i] = didSuffix[1 + i];
        }

        return bytes32(did);
    }

    function sigToBase64URLEncoded(bytes calldata rs) public pure returns (bytes memory) {
        return bytes(Base64.encodeURL(rs));
    }
}
