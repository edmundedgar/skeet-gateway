// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Contract to verify DID updates

// *******************************************************************************************
//
// WARNING: DO NOT USE THIS WITHOUT UNDERSTANDING ITS LIMITATIONS
//
// ALL KINDS OF THINGS YOU WOULD NORMALLY ASSUME ABOUT DID DIRECTORY UPDATES DO NOT APPLY HERE
//
// *******************************************************************************************

// https://web.plc.directory/spec/v0.1/did-plc
// https://ipld.io/specs/codecs/dag-cbor/spec/

import {DagCborNavigator} from "./DagCborNavigator.sol";
import {DidFormats} from "./DidFormats.sol";

import {Secp256k1PubkeyChecker} from "./Secp256k1PubkeyChecker.sol";

import {console} from "forge-std/console.sol";

// For performance reasons we search for fieldnames by their encoded bytes starting with the CBOR header byte
// eg "sig" is encoded with 63 (CBOR for 3-byte text) followed by 736967 ("sig" in UTF-8).
bytes4 constant CBOR_HEADER_SIG_4B = bytes4(hex"63736967"); // text, sig
bytes5 constant CBOR_HEADER_PREV_5B = bytes5(hex"6470726576"); // text, prev
bytes13 constant CBOR_HEADER_ROTATIONKEYS_13B = bytes13(hex"6c726f746174696f6e4b657973"); // text, rotationKeys

contract DidVerifier is DidFormats, Secp256k1PubkeyChecker {
    /// @notice Calculate the hash used to make the CID of a DID update operation
    /// @dev This handles a CBOR operation with its signature stripped, which you do not usually encounter in nature
    /// @param entry CBOR-encoded bytes representing the operation, without its signature
    /// @param sigRS The r and s parameters (32 bytes each) of the signature of the update
    /// @param insertAtIdx The index where the signature should be added to recover the signed CBOR (so far always 1)
    /// @return The hash that will be used to calculate a CID (this part will require extra encoding steps)
    function calculateCIDSha256(bytes calldata entry, bytes calldata sigRS, uint256 insertAtIdx)
        public
        pure
        returns (bytes32)
    {
        // The mapping has 1 more entry
        bytes1 mappingHeaderWithSig = bytes1(uint8(bytes1(entry[0:1])) + 1);

        bytes memory encodedSig = sigToBase64URLEncoded(sigRS);
        return sha256(
            bytes.concat(
                mappingHeaderWithSig,
                entry[1:insertAtIdx],
                CBOR_HEADER_SIG_4B,
                bytes(hex"78"),
                bytes1(uint8(encodedSig.length)),
                encodedSig,
                entry[insertAtIdx:]
            )
        );
    }

    /// @notice Verify that an operation is signed with a key from an earlier update listed in its "prev" field
    /// @param entry CBOR-encoded bytes representing the operation, without its signature
    /// @param sig a signature, made up of 32 bytes r, 32 bytes s and 1 byte v
    /// @param prev the CID that should be specified in the "prev" field of this entry
    /// @param rotationKey The address corresponding to the pubkey that signed this entry
    function verifyEntry(bytes calldata entry, bytes calldata sig, bytes32 prev, address rotationKey) public pure {
        uint256 cursor;
        uint256 nextLen;

        require(prev != bytes32(0), "prev not set");
        require(rotationKey != address(0), "rotation key not set");

        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(bytes1(sig[64:65]));

        require(ecrecover(sha256(entry), v, r, s) == rotationKey, "Signature did not match rotation key");

        // Now make sure that the prev in this entry matches the CID of the previous entry
        // Unlike the CID encoding in status updates, the DID updates CBOR-encoding a string that was already encoded
        string memory cid = sha256ToBase32CID(prev);

        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_PREV_5B), 1);
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(bytes(cid).length == nextLen, "prev length mismatch");
        require(
            keccak256(entry[cursor:cursor + nextLen]) == keccak256(bytes(cid)),
            "prev hash does not match supplied entry"
        );
    }

    /// @notice Return the address of the rotation key that will be used to sign the next entry
    /// @dev The key is passed in as a parameter but this will check it is actually listed in this update
    /// @param entry CBOR-encoded bytes representing the operation, without its signature
    /// @param pubkey Pubkey of the expected rotation key, with compression prefix + uncompressed pubkey
    /// @param rotationKeyIdx The address corresponding to the pubkey that signed this entry
    /// @return The address corresponding to this key that we can use to check the next signature with ecrecover
    function extractRotationKey(bytes calldata entry, bytes calldata pubkey, uint256 rotationKeyIdx)
        public
        pure
        returns (address)
    {
        // TODO: Might be able to save from cbor reading by passing in an later cursor
        uint256 cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_ROTATIONKEYS_13B), 1);

        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(numEntries > rotationKeyIdx, "Rotation key index higher than the highest rotation key we found");

        uint256 nextLen;
        for (uint256 i = 0; i <= rotationKeyIdx; i++) {
            (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
            if (i == rotationKeyIdx) {
                string memory encodedKey = pubkeyBytesToDidKey(pubkey[0:33]);
                require(nextLen == bytes(encodedKey).length, "pubkey not expected length");
                require(
                    keccak256(entry[cursor:cursor + nextLen]) == keccak256(bytes(encodedKey)),
                    "Key not found at expected index"
                );

                // The did:key entries are expressed as compressed pubkey
                // (1-byte 02 or 03 prefix + 32 byte x coordinate)
                // ecrecover returns an Ethereum address which is made by hashing an uncompressed pubkey
                // (32 byte x coordinate + 32 byte y coordinate)
                // We pass in the 1-byte prefix, the 32-byte x coordinate and the 32-byte y coordinate
                // It is probably safe to just assume the y coordinate is legit...
                // ...as you should not be able to find an address collision no matter what you pass in there.
                // But checking it is cheap and simple so out of an excess of caution we take just this function from an unaudited Secp256k1 lib
                require(
                    isPubkeyOnCurve(uint256(bytes32(pubkey[1:33])), uint256(bytes32(pubkey[33:65]))),
                    "Suspicious uncompressed pubkey"
                );
                return address(uint160(uint256(keccak256(pubkey[1:]))));
            } else {
                cursor = cursor + nextLen;
            }
        }

        revert("This should be unreachable");
    }

    // We assume the first entry is already verified.
    // This can have come either from the genesis operation producing a DID or being set later by the signer.
    // You probably only stored its hash so I hope you checked the hash you stored matches the entry before you passed it here
    // Return the sighash (the hash of the update without its signature, not the CID which includes it) of the resulting entry
    // NB we store sighashes not CIDs because the CIDs might get malleated (possibly, not sure???)

    /// @notice Return the address of the rotation key that will be used to sign the next entry
    /// @param entries CBOR-encoded bytes representing operations, without their signatures
    /// @param sigs Signatures for each update: 32-byte r, 32-byte s, 1-byte v
    /// @param pubkeys Pubkeys of the key signing each operation, with compression prefix + uncompressed pubkey
    /// @param pubkeyIndexes The indexes of which key entry provides the rotation key that sigs the next entry
    /// @param insertAtIdx The byte position to reinsert the signatures to make the CID referred to in future updates
    /// @return The hash of the final signed entry, ready to be base-32-encoded into a CID
    function verifyDidTransition(
        bytes[] calldata entries,
        bytes[] calldata sigs,
        bytes[] calldata pubkeys,
        uint256[] calldata pubkeyIndexes,
        uint256[] calldata insertAtIdx
    ) public pure returns (bytes32) {
        bytes32 nextPrev;
        address nextRotationKey;

        require(entries.length > 1, "You need at least 2 entries to prove a transition");

        for (uint256 i = 0; i < entries.length; i++) {
            // The first entry must be the one we already have and you should already have verified it

            if (i > 0) {
                verifyEntry(entries[i], sigs[i], nextPrev, nextRotationKey);
            }

            // To validate "prev" in the next entry we'll need the hash corresponding to the CID
            // entries[i] has the signature removed, so we need to put it back in then hash the resulting CBOR
            nextPrev = calculateCIDSha256(entries[i], sigs[i][0:64], insertAtIdx[i]);

            // Last item
            // Nothing we handle this time gets signed by these rotation keys so return without reading them
            if (i == entries.length - 1) {
                return nextPrev;
            }

            // TODO: The first rotation key entry is never read
            // We could pass in a shorter array and stop adding +1 to the index (likewise for pubkeys)
            nextRotationKey = extractRotationKey(entries[i], pubkeys[i + 1], pubkeyIndexes[i + 1]);
        }

        revert("This should be unreachable");
    }
}
