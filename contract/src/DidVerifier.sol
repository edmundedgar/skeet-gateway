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

import {console} from "forge-std/console.sol";

// For performance reasons we search for fieldnames by their encoded bytes starting with the CBOR header byte
// eg "sig" is encoded with 63 (CBOR for 3-byte text) followed by 736967 ("sig" in UTF-8).
bytes4 constant CBOR_HEADER_SIG_4B = bytes4(hex"63736967"); // text, sig
bytes5 constant CBOR_HEADER_PREV_5B = bytes5(hex"6470726576"); // text, prev
bytes13 constant CBOR_HEADER_ROTATIONKEYS_13B = bytes13(hex"6c726f746174696f6e4b657973"); // text, rotationKeys

bytes20 constant CBOR_HEADER_VERIFICATIONMETHODS_20B = bytes20(hex"73766572696669636174696f6e4d6574686f6473"); // text, verificationMethods
bytes8 constant CBOR_HEADER_ATPROTO_8B = bytes8(hex"67617470726F746F");

contract DidVerifier is DidFormats {
    function separateSignature(bytes calldata entry) internal pure returns (bytes calldata, bytes32, uint256) {
        bytes1 mappingHeaderWithoutSig = bytes1(uint8(bytes1(entry[0:1])) - 1);
        uint256 cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_SIG_4B), 1);

        uint256 nextLen;

        // This advances to the end of the CBOR_HEADER_SIG_4B so we need to back up 4 bytes to find what we need to remove
        uint256 sigNameValueStart = cursor - 4;
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        uint256 sigEnd = cursor + nextLen;
        bytes32 entryHash = sha256(bytes.concat(mappingHeaderWithoutSig, entry[1:sigNameValueStart], entry[sigEnd:]));
        return (entry[cursor:sigEnd], entryHash, sigEnd);
    }

    function verifyPrev(bytes calldata entry, bytes32 nextPrev, uint256 cursor) internal pure {
        // If there's no prev it's the first time and there's nothing to verify
        if (nextPrev == bytes32(0)) {
            return;
        }
        uint256 nextLen;
        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_PREV_5B), cursor);
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        string memory cid = sha256ToBase32CID(nextPrev);
        require(bytes(cid).length == nextLen, "prev length mismatch");
        require(
            keccak256(entry[cursor:cursor + nextLen]) == keccak256(bytes(cid)),
            "prev hash does not match supplied entry"
        );
    }

    // todo: sig should just be v if that
    function processSignedCBOR(bytes calldata entry, uint8 sigv, bytes32 nextPrev, address nextKey)
        public
        pure
        returns (bytes32, uint256)
    {
        bytes32 entryHash;
        bytes calldata sig;
        uint256 cursor;

        (sig, entryHash, cursor) = separateSignature(entry);

        if (nextPrev != bytes32(0)) {
            // If we didn't get a prev (and rotationKey) it means it's the first item, which we don't have to verify
            require(nextKey != address(0), "Rotation key for verification not supplied");
            verifySignature(sig, sigv, entryHash, nextKey);
            verifyPrev(entry, nextPrev, cursor);
        }

        return (entryHash, cursor);
    }

    /// @notice Verify that an operation is signed by the specified key
    /// @param sigRS a signature, made up of 32 bytes r, 32 bytes s and 1 byte v
    /// @param v a signature v param
    /// @param entryHash CBOR-encoded bytes representing the operation, without its signature
    /// @param rotationKey The address corresponding to the pubkey that signed this entry
    function verifySignature(bytes calldata sigRS, uint8 v, bytes32 entryHash, address rotationKey) public pure {
        // If there's no rotationKey it's the first time and there's nothing to verify
        if (rotationKey == address(0)) {
            return;
        }

        require(rotationKey != address(0), "rotation key not set");

        bytes32 r = bytes32(sigRS[0:32]);
        bytes32 s = bytes32(sigRS[32:64]);

        require(ecrecover(entryHash, v, r, s) == rotationKey, "Signature did not match rotation key");
    }

    /// @notice Return the address of the rotation key that will be used to sign the next entry
    /// @dev The key is passed in as a parameter but this will check it is actually part of the entry before converting it to an address
    /// @param entry CBOR-encoded bytes representing the operation, without its signature
    /// @param pubkey Uncompressed pubkey of the expected rotation key
    /// @param rotationKeyIdx The address corresponding to the pubkey that signed this entry
    /// @param cursor The index to start looking for entry, will be for some earlier field
    /// @return The address corresponding to this key that we can use to check the next signature with ecrecover
    function extractRotationKey(bytes calldata entry, bytes calldata pubkey, uint256 rotationKeyIdx, uint256 cursor)
        public
        pure
        returns (address)
    {
        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_ROTATIONKEYS_13B), cursor);

        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(numEntries > rotationKeyIdx, "Rotation key index higher than the highest rotation key we found");

        uint256 nextLen;
        for (uint256 i = 0; i <= rotationKeyIdx; i++) {
            (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
            if (i == rotationKeyIdx) {
                string memory encodedKey = pubkeyBytesToDidKey(pubkey);
                require(nextLen == bytes(encodedKey).length, "pubkey not expected length");
                require(
                    keccak256(entry[cursor:cursor + nextLen]) == keccak256(bytes(encodedKey)),
                    "Key not found at expected index"
                );

                // The did:key entries are expressed as compressed pubkey
                // (1-byte 02 or 03 prefix + 32 byte x coordinate)
                // When we need to check that something was signed with this key we will use ecrecover.
                // ecrecover returns an Ethereum address which is made by hashing an uncompressed pubkey
                // (32 byte x coordinate + 32 byte y coordinate)
                // We pass in the uncompressed pubkey which is used in the hash to make the address.
                // The y part is not found in the did:key entry that we extract from the CBOR
                // It is probably safe to just assume the y coordinate is legit without validating it...
                // ...as an attacker should not be able to find an address collision so passing hostile input can't help them.
                // But it's cheap to check and the isPubkeyOnCurve code is simple so we'll check it out of an excess of caution.
                require(isPubkeyOnCurve(pubkey), "Suspicious uncompressed pubkey");
                return address(uint160(uint256(keccak256(pubkey))));
            } else {
                cursor = cursor + nextLen;
            }
        }

        revert("This should be unreachable");
    }

    function extractVerificationMethod(bytes calldata entry, bytes calldata pubkey, uint256 cursor)
        public
        pure
        returns (address)
    {
        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_VERIFICATIONMETHODS_20B), cursor);

        uint256 nextLen;
        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(numEntries > 0, "WTF no verificationMethods");

        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_ATPROTO_8B), cursor);
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        string memory encodedKey = pubkeyBytesToDidKey(pubkey);
        require(nextLen == bytes(encodedKey).length, "pubkey not expected length");
        require(
            keccak256(entry[cursor:cursor + nextLen]) == keccak256(bytes(encodedKey)), "Key not found at expected index"
        );
        require(isPubkeyOnCurve(pubkey), "Suspicious uncompressed pubkey");
        return address(uint160(uint256(keccak256(pubkey))));
    }
}
