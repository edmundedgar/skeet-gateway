// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Contract to verify DID updates
// https://web.plc.directory/spec/v0.1/did-plc
// https://ipld.io/specs/codecs/dag-cbor/spec/

import {DagCborNavigator} from "./DagCborNavigator.sol";
import {DidFormats} from "./DidFormats.sol";

import {SECP256K1} from "0xcyphered/secp256k1-solidity/contracts/SECP256K1.sol";

import {console} from "forge-std/console.sol";

bytes1 constant CBOR_MAPPING_2_ENTRIES_1B = hex"a2";
bytes1 constant CBOR_MAPPING_14_ENTRIES_1B = hex"ae";

// For performance reasons we search for fieldnames by their encoded bytes starting with the CBOR header byte
// eg "sig" is encoded with 63 (CBOR for 3-byte text) followed by 736967 ("sig" in UTF-8).
bytes4 constant CBOR_HEADER_SIG_4B = bytes4(hex"63736967"); // text, sig
bytes5 constant CBOR_HEADER_PREV_5B = bytes5(hex"6470726576"); // text, prev
bytes13 constant CBOR_HEADER_ROTATIONKEYS_13B = bytes13(hex"6c726f746174696f6e4b657973"); // text, rotationKeys

contract DidVerifier is DidFormats {
    function calculateCIDSha256(bytes calldata entry, bytes calldata sigRS, uint256 insertAtIdx)
        public
        pure
        returns (bytes32)
    {
        // The mapping has 1 more entry
        bytes1 mappingHeaderWithSig = bytes1(uint8(bytes1(entry[0:1])) + 1);

        bytes memory encodedSig = sigToBase64URLEncoded(sigRS);
        return sha256(bytes.concat(mappingHeaderWithSig, entry[1:insertAtIdx], encodedSig, entry[insertAtIdx:]));
    }

    function verifyEntry(bytes calldata entry, bytes calldata sig, bytes32 nextPrev, bytes memory nextRotationKey)
        public
        pure
    {
        uint256 cursor;
        uint256 nextLen;

        require(nextPrev != bytes32(0), "prev not set");
        require(nextRotationKey.length > 0, "rotation key not set");

        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(bytes1(sig[64:65]));
        console.log(v);
        console.logBytes32(r);
        console.logBytes32(s);

        uint256 pubkeyL;
        uint256 pubkeyR;
        (pubkeyL, pubkeyR) = SECP256K1.recover(uint256(sha256(entry)), v, uint256(r), uint256(s));

        // This probably needs the initial 03 etc slicing off the start of nextRotationKey
        require(bytes32(pubkeyL) == bytes32(nextRotationKey), "Signature did not match rotation key");

        // encode nextPrev to a cid with the Base32 lib at https://github.com/0x00000002/ipfs-cid-solidity/blob/main/contracts/Base32.sol
        // search for prev: nextPrev in the cbor

        // Now make sure that the prev in this entry matches the CID of the previous entry
        // Unlike the CID encoding in status updates, the DID updates CBOR-encoding a string that was already encoded
        // eg https://cid.ipfs.tech/?ref=filebase.com#bafyreid6gk6me7qotoejyh4tbmohuniu37anfgb6lhr2po3btqannss3dq
        string memory cid = sha256ToBase32CID(nextPrev);

        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_PREV_5B), 1);
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(bytes(cid).length == nextLen, "prev length mismatch");
        require(
            keccak256(entry[cursor:cursor + nextLen]) == keccak256(bytes(cid)),
            "prev hash does not match supplied entry"
        );
    }

    // TODO: Might be able to save from cbor reading by passing in an later cursor
    function extractRotationKey(bytes calldata entry, uint256 nextRotationKeyIdx) public pure returns (bytes memory) {
        // Get the rotation key that will be used to sign the next entry
        // TODO: The first rotation key entry is never read
        // We couli pass in an arra

        uint256 cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_ROTATIONKEYS_13B), 1);
        console.log("rotation keys start ");
        console.log(cursor);

        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(numEntries > nextRotationKeyIdx, "Rotation key index higher than the highest rotation key we found");
        console.log("found # keys:");
        console.log(numEntries);

        uint256 nextLen;
        for (uint256 i = 0; i <= nextRotationKeyIdx; i++) {
            (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
            console.log(nextLen);
            if (i == nextRotationKeyIdx) {
                console.logBytes(entry[cursor:cursor + nextLen]);
                // strip the did:key:
                require(nextLen > 10, "Key should be at least 10 bytes, probably lots more");
                require(bytes8(entry[cursor:cursor + 8]) == bytes8(bytes("did:key:")), "did should start with did:key:");
                uint256 keyEnd = cursor + nextLen;
                // console.log("pubky:");
                // console.logBytes(didKeyToBytes(string(entry[cursor+9:keyEnd])));
                return didKeyToBytes(string(entry[cursor + 9:keyEnd]));
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
    function verifyDidTransition(
        bytes[] calldata entries,
        bytes[] calldata sigs,
        uint256[] calldata rotationKeyIndexes,
        uint256[] calldata insertAtIdx
    ) public pure returns (bytes32) {
        bytes32 nextPrev;
        bytes memory nextRotationKey;

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

            nextRotationKey = extractRotationKey(entries[i], rotationKeyIndexes[i + 1]);
            console.log("rot key");
            console.logBytes(nextRotationKey);
        }

        revert("This should be unreachable");
    }
}
