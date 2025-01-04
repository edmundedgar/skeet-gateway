// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Contract to verify DID updates
// https://web.plc.directory/spec/v0.1/did-plc
// https://ipld.io/specs/codecs/dag-cbor/spec/

import {DagCborNavigator} from "./DagCborNavigator.sol";
import {DidFormats} from "./DidFormats.sol";

import {console} from "forge-std/console.sol";

bytes1 constant CBOR_MAPPING_2_ENTRIES_1B = hex"a2";
bytes1 constant CBOR_MAPPING_14_ENTRIES_1B = hex"ae";

// For performance reasons we search for fieldnames by their encoded bytes starting with the CBOR header byte
// eg "sig" is encoded with 63 (CBOR for 3-byte text) followed by 736967 ("sig" in UTF-8).
bytes4 constant CBOR_HEADER_SIG_4B = bytes4(hex"63736967"); // text, sig
bytes5 constant CBOR_HEADER_PREV_5B = bytes5(hex"6470726576"); // text, prev
bytes13 constant CBOR_HEADER_ROTATIONKEYS_13B = bytes13(hex"6c726f746174696f6e4b657973"); // text, rotationKeys

contract DidVerifier is DidFormats {

    function calculateCIDSha256(bytes calldata entry, bytes calldata sigRS, uint256 insertAtIdx) public pure returns (bytes32){

        // The mapping has 1 more entry 
        bytes1 mappingHeaderWithSig = bytes1(uint8(bytes1(entry[0:1]))+1);

        bytes memory encodedSig = sigToBase64URLEncoded(sigRS);
        return sha256(bytes.concat(mappingHeaderWithSig, entry[1:insertAtIdx], encodedSig, entry[insertAtIdx:]));

    }

    function verifyEntry(bytes calldata entry, bytes calldata sig, bytes32 nextPrev, address nextRotationKey) pure public {
        uint256 cursor;
        uint256 nextLen;

        require(nextPrev != bytes32(0), "prev not set");
        require(nextRotationKey != address(0), "rotation key not set");

        require(ecrecover(sha256(entry), uint8(bytes1(sig[64:65])), bytes32(sig[0:32]), bytes32(sig[32:64])) == nextRotationKey, "Signature did not match rotation key");

        // Now make sure that the prev in this entry matches the CID of the previous entry
        // Unlike the CID encoding in status updates, the DID updates CBOR-encoding a string that was already encoded
        // eg https://cid.ipfs.tech/?ref=filebase.com#bafyreid6gk6me7qotoejyh4tbmohuniu37anfgb6lhr2po3btqannss3dq

        cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_PREV_5B), cursor);
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        bytes32 prev = base32CidToSha256(string(entry[cursor:cursor + nextLen]));

        require(prev == nextPrev, "prev hash does not match supplied prev entry");
    }

    // TODO: Might be able to save from cbor reading by passing in an later cursor
    function extractRotationKey(bytes calldata entry, uint256 nextRotationKeyIdx) public pure returns (address) {

        // Get the rotation key that will be used to sign the next entry
        // TODO: The first rotation key entry is never read 
        // We couli pass in an arra

        uint256 cursor = DagCborNavigator.indexOfMappingField(entry, bytes.concat(CBOR_HEADER_ROTATIONKEYS_13B), 0);

        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
        require(numEntries > nextRotationKeyIdx, "Rotation key index higher than the highest rotation key we found");

        uint256 nextLen;
        for(uint256 i=0; i<=nextRotationKeyIdx; i++) {
            (, nextLen, cursor) = DagCborNavigator.parseCborHeader(entry, cursor);
            if (i == nextRotationKeyIdx) {
                return didKeyToAddress(string(entry[cursor:cursor + nextLen]));
            } else {
                cursor = cursor + nextLen;
            }
        }

    }

    // We assume the first entry is already verified.
    // This can have come either from the genesis operation producing a DID or being set later by the signer.
    // You probably only stored its hash so I hope you checked the hash you stored matches the entry before you passed it here
    // Return the sighash (the hash of the update without its signature, not the CID which includes it) of the resulting entry
    // NB we store sighashes not CIDs because the CIDs might get malleated (possibly, not sure???)
    function verifyDidTransition(bytes[] calldata entries, bytes[] calldata sigs, uint256[] calldata rotationKeyIndexes, uint256[] calldata insertAtIdx) pure public returns (bytes32) {

        bytes32 nextPrev;
        address nextRotationKey;

        require(entries.length > 1, "You need at least 2 entries to prove a transition");

        for(uint256 i=0; i<entries.length; i++) {

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

        }

        revert("This should be unreachable");

    }

}
