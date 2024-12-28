// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Contract to extract DAG-CBOR-encoded Atproto Merkle Search Tree data
// https://atproto.com/specs/repository
// https://ipld.io/specs/codecs/dag-cbor/spec/

// The order of keys is fixed as per the DAG-CBOR spec.
// Most data is encoded in mappings with a known, fixed-width name field followed by a field of known length.
// When the lengths are known we can just read the bytes representing the value we need directly and skip the name field.
// We will sometimes sanity-check the name field with assert() although this is not strictly necessary.
// However there are some cases we encounter where data lengths vary:
// - For nullable CIDs we need to check for null
// - For strings and byte arrays we need to extract the length from the header
// - For integers with unknown values (just the p field) the data itself needs to be extracted from the header.
// - For arrays the length of the array needs to be extracted from the header.
// We extract these values with DagCborNavigator.parseCborHeader()
// The meaning of the value we get from the header will vary depending on the type of the field:
// - For our integer (p) it will return the value of the field and there will be no additional payload.
// - For strings and byte arrays it will return the number of bytes in the payload.
// - For arrays it will return the number of entries in the array.

import {DagCborNavigator} from "./DagCborNavigator.sol";
import {console} from "forge-std/console.sol";

bytes1 constant CBOR_NULL_1B = hex"f6";

// CBOR mappings are encoded with the following initial bytes, indicating the number of entries:
bytes1 constant CBOR_MAPPING_2_ENTRIES_1B = hex"a2"; // tree node has 2 fields
bytes1 constant CBOR_MAPPING_4_ENTRIES_1B = hex"a4"; // tree node entry field has 4 fields
bytes1 constant CBOR_MAPPING_5_ENTRIES_1B = hex"a5"; // sig node has 5 fields when unsigned
bytes1 constant CBOR_MAPPING_15_ENTRIES_1B = hex"af"; // data node has 4 to 5 fields but they might increase it

// For performance reasons we search for fieldnames by their encoded bytes starting with the CBOR header byte
// eg "did" is encoded with 63 (CBOR for 3-byte text) followed by 646964 ("did" in UTF-8).

// Tree nodes contain e and l
bytes2 constant CBOR_HEADER_E_2B = bytes2(hex"6165");
bytes2 constant CBOR_HEADER_L_2B = bytes2(hex"616c");
bytes3 constant CBOR_HEADER_L_NULL_3B = bytes3(hex"616cf6"); // l followed by a null

// Each e entry contains k, p, t, v
bytes2 constant CBOR_HEADER_K_2B = bytes2(hex"616b");
bytes2 constant CBOR_HEADER_P_2B = bytes2(hex"6170");
bytes2 constant CBOR_HEADER_T_2B = bytes2(hex"6174");
bytes2 constant CBOR_HEADER_V_2B = bytes2(hex"6176");

// Commit nodes contain did, rev, data, prev and version (which must be 3)
bytes4 constant CBOR_HEADER_DID_4B = bytes4(hex"63646964"); // text, did
bytes4 constant CBOR_HEADER_REV_4B = bytes4(hex"63726576"); // text, rev
bytes5 constant CBOR_HEADER_DATA_5B = bytes5(hex"6464617461"); // text, data
bytes5 constant CBOR_HEADER_PREV_5B = bytes5(hex"6470726576"); // text, prev
bytes9 constant CBOR_HEADER_AND_VALUE_VERSION_3_9B = bytes9(hex"6776657273696f6e03"); // text, version, 3

// content cbor contains text
bytes5 constant CBOR_HEADER_TEXT_5B = bytes5(hex"6474657874"); // text, "text"

// CID IDs are 32-byte hashes which we will find preceded by some special CBOR tag data then the multibyte prefix
bytes9 constant CID_PREFIX_BYTES_9B = hex"d82a58250001711220"; // CBOR CID header stuff then the length (37)
uint256 constant CID_HASH_LENGTH = 32;

abstract contract AtprotoMSTProver {
    /// @notice Return a substring of a string
    /// @param str The string
    /// @param startIndex The start index of the substring
    /// @param endIndex The end index of the substring
    /// @return The substring
    function _substring(string memory str, uint256 startIndex, uint256 endIndex)
        internal
        pure
        returns (string memory)
    {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    /// @notice Parse the content CBOR and return the value of the "text" field
    /// @param content The CBOR-encoded content whose value we want
    /// @return The start of the text field
    /// @return The end of the text field
    function indexOfMessageText(bytes calldata content) internal pure returns (uint256, uint256) {
        uint256 cursor;
        uint256 nextLen;

        // Mapping byte
        // Typically these have 4 or 5 fields (depending whether they are replies).
        // We only care about 1, the text, which we expect to come first.
        // We'll sanity-check that the range is somewhere from 2 to 15.
        bytes1 mappingByte = bytes1(content[cursor:cursor + 1]);
        assert(uint8(mappingByte) >= uint8(CBOR_MAPPING_2_ENTRIES_1B));
        assert(uint8(mappingByte) <= uint8(CBOR_MAPPING_15_ENTRIES_1B));
        cursor = 1;

        // Extract the message from the CBOR
        // This is in the "text" field
        // This always seems to be at the start of the message (because "text" is a fairly short key)
        // But in theory there could be other things ahead of it
        cursor = DagCborNavigator.indexOfMappingField(content, bytes.concat(CBOR_HEADER_TEXT_5B), cursor);
        (, nextLen, cursor) = DagCborNavigator.parseCborHeader(content, cursor);
        return (cursor, cursor + nextLen);
    }

    /// @notice Check that the supplied commit node includes the supplied root hash, or revert if it doesn't.
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param commitNode The CBOR-encoded commit node
    function assertCommitNodeContainsData(bytes32 proveMe, bytes calldata commitNode) public pure {
        uint256 cursor;
        uint256 extra;

        // The unsigned commit node has 5 entries.
        // A 6th entry, "sig", is added later by hashing the unsigned, 5-entry version.
        assert(bytes1(commitNode[cursor:cursor + 1]) == CBOR_MAPPING_5_ENTRIES_1B);
        cursor = 1;

        assert(bytes5(commitNode[cursor:cursor + 4]) == CBOR_HEADER_DID_4B);
        cursor = cursor + 4;
        (, extra, cursor) = DagCborNavigator.parseCborHeader(commitNode, cursor);
        cursor = cursor + extra;

        assert(bytes4(commitNode[cursor:cursor + 4]) == CBOR_HEADER_REV_4B);
        cursor = cursor + 4;
        (, extra, cursor) = DagCborNavigator.parseCborHeader(commitNode, cursor);
        cursor = cursor + extra;

        assert(bytes8(commitNode[cursor:cursor + 5]) == CBOR_HEADER_DATA_5B);
        cursor = cursor + 5;
        assert(bytes9(commitNode[cursor:cursor + 9]) == CID_PREFIX_BYTES_9B);
        cursor = cursor + 9;
        require(
            bytes32(commitNode[cursor:cursor + CID_HASH_LENGTH]) == proveMe, "Data field does not contain expected hash"
        );
        cursor = cursor + CID_HASH_LENGTH;

        assert(bytes5(commitNode[cursor:cursor + 5]) == CBOR_HEADER_PREV_5B);
        cursor = cursor + 5;
        if (bytes1(commitNode[cursor:cursor + 1]) == CBOR_NULL_1B) {
            cursor = cursor + 1;
        } else {
            assert(bytes9(commitNode[cursor:cursor + 9]) == CID_PREFIX_BYTES_9B);
            cursor = cursor + 9;
            cursor = cursor + CID_HASH_LENGTH; // cid we don't care about
        }

        require(bytes9(commitNode[cursor:cursor + 9]) == CBOR_HEADER_AND_VALUE_VERSION_3_9B, "v3 field not found"); // text "version" 3
    }

    /// @notice Verify the path from the hash of the node provided (index 0) up towards the root, to the final node provided.
    /// @dev The final node is intended to be the root node of the MST tree, but you must verify this by checking the signed commit node
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param nodes An array of CBOR-encoded tree nodes, each containing an entry for the hash of an earlier one
    /// @return rootNode The final node of the series, intended (but not verified) to be the root node
    /// @return rkey The record key of the tip node
    function merkleProvenRootHash(bytes32 proveMe, bytes[] calldata nodes, uint256[] calldata hints)
        public
        pure
        returns (bytes32, string memory)
    {
        string memory rkey;

        // We work up the chain towards the root, finding the "proveMe" hash in the appropriate place.
        // Each time we find it we hash the current node and use it as the next "proveMe" value to check at the next level up.

        // For the first node (node 0), we need to find the hash we want in the "v" field of one of the entries.
        // However we also need to look at the preceding entries in the node to recover the rkey (see below).
        // For subsequent nodes, we need to find the hash in either the "l" field or the "t" field of one of the entries.

        for (uint256 n = 0; n < nodes.length; n++) {
            // The hints are indexes telling us where we can look to find the data we need for verification.
            // This avoids the need to read data from a lot of entries just to discover that they aren't what we're looking for.
            // The hints could be malicious, but if they are wrong then we will simply not find the data and verification will fail.
            // We use 0 to represent the "l" field of the node.
            // Any other number represents the index of one of the entries, offset by 1.

            uint256 hint = hints[n];

            uint256 numEntries;

            // parseCborHeader either tells us the length of the data, or tells us the data itself if it could fit in the header.
            // It also advances the cursor to the end of the header.
            // If there is a payload (ie the answer wasn't in the header)...
            // ...we then read the data manually as a calldata slice and advance the cursor to the end of the payload.
            uint256 extra;
            uint256 cursor;

            // mapping byte for 2 entries, k and e
            assert(bytes1(nodes[n][cursor:cursor + 1]) == CBOR_MAPPING_2_ENTRIES_1B);
            cursor = cursor + 1;

            // Optimization to avoid looping through entries advancing the cursor unnecessarily:
            // For a left node, the field should be at the very end of the data.
            // If it's there we can just check the l: <multihash etc><cid> we expect.
            // The wrinkle is that it could be null.
            // We can't check for null without knowing where the data starts because the bytes meaning null might randomly be part of our CID.
            // So try the optimized way, but if we find the null bytes, fall back on cycling through all the nodes then reading l at the end.
            // This saves an average of 176330 gas if we insist on sanity-checking everything in the loop with assert().
            // If we run with the asserts() removed it only saves 12531 gas which may not be worth the complexity.
            if (n > 0 && hint == 0) {
                uint256 lastByte = nodes[n].length;
                if (bytes3(nodes[n][lastByte - 3:lastByte]) != bytes3(CBOR_HEADER_L_NULL_3B)) {
                    require(bytes32(nodes[n][lastByte - 32:lastByte]) == proveMe, "l value mismatch");
                    require(bytes9(nodes[n][lastByte - 32 - 9:lastByte - 32]) == bytes9(CID_PREFIX_BYTES_9B), "Unexpected CID prefix");
                    require(
                        bytes2(nodes[n][lastByte - 32 - 9 - 2:lastByte - 32 - 9]) == CBOR_HEADER_L_2B,
                        "l prefix mismatch"
                    );
                    proveMe = sha256(nodes[n]);
                    continue;
                }
            }

            assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_E_2B);
            cursor = cursor + 2;
            (, numEntries, cursor) = DagCborNavigator.parseCborHeader(nodes[n], cursor); // e array header

            // If the node is in an "e" entry, we only have to loop as far as the index of the entry we want
            // If the node is in the "l", we'll have to go through them all to find where "l" starts
            require(hint <= numEntries, "Hint is for an index beyond the end of the entries");
            if (hint > 0) {
                numEntries = hint;
            }

            for (uint256 i = 0; i < numEntries; i++) {
                // mapping byte for a mapping with 4 keys
                assert(bytes1(nodes[n][cursor:cursor + 1]) == CBOR_MAPPING_4_ENTRIES_1B);
                cursor = cursor + 1;

                // For the first node, which contains information about the skeet, we also need the record key (k) in the relevant entry.
                // This uses a compression scheme where we have to construct it from the k and p of earlier entries.
                // For all later nodes we can ignore the value but we still have to check the field lengths to know how far to advance the cursor.

                if (n == 0) {
                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_K_2B);
                    cursor = cursor + 2;

                    (, extra, cursor) = DagCborNavigator.parseCborHeader(nodes[n], cursor);
                    string memory kval = string(nodes[n][cursor:cursor + extra]);
                    cursor = cursor + extra;

                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_P_2B);
                    cursor = cursor + 2;
                    // p is an int so there is no payload and the "extra" denotes the value not the length,
                    // Since there is no payload we don't advance the cursor beyond what parseCborHeader told us
                    (, extra, cursor) = DagCborNavigator.parseCborHeader(nodes[n], cursor);
                    uint8 pval = uint8(extra);

                    // Compression scheme used by atproto:
                    // Take the first bytes specified by the partial from the existing rkey
                    // Then append the bytes found in the new k value
                    if (pval == 0) {
                        rkey = kval;
                    } else {
                        string memory oldr = _substring(rkey, 0, uint256(pval));
                        rkey = string.concat(oldr, kval);
                    }
                } else {
                    ///assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_K_2B);
                    cursor = cursor + 2;

                    // Variable-length string
                    (, extra, cursor) = DagCborNavigator.parseCborHeader(nodes[n], cursor);
                    cursor = cursor + extra;

                    ///assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_P_2B);
                    cursor = cursor + 2;

                    // For an int the val is in the header so we don't need to advance cursor beyond what parseCborHeader did
                    (, , cursor) = DagCborNavigator.parseCborHeader(nodes[n], cursor); // val
                }

                ///assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_T_2B);
                cursor = cursor + 2;

                if (bytes1(nodes[n][cursor:cursor + 1]) == CBOR_NULL_1B) {
                    cursor = cursor + 1;
                } else {
                    assert(bytes9(nodes[n][cursor:cursor + 9]) == CID_PREFIX_BYTES_9B);
                    cursor = cursor + 9;

                    // Our 32 bytes
                    if (n > 0 && hint > 0 && i == hint - 1) {
                        bytes32 val = bytes32(nodes[n][cursor:cursor + CID_HASH_LENGTH]);
                        require(val == proveMe, "Value does not match target");
                        proveMe = sha256(nodes[n]);
                        continue;
                    }

                    cursor = cursor + CID_HASH_LENGTH;
                }

                // non-nullable v
                ///assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_V_2B);
                cursor = cursor + 2;

                ///assert(bytes9(nodes[n][cursor:cursor + 9]) == CID_PREFIX_BYTES_9B);
                cursor = cursor + 9;

                // 32 bytes that we only care about if it's the winning entry of the data node (node 0)
                if (n == 0 && i == hint - 1) {
                    // Our 32 bytes
                    bytes32 val = bytes32(nodes[n][cursor:cursor + CID_HASH_LENGTH]);
                    require(val == proveMe, "e val does not match");
                    proveMe = sha256(nodes[0]);
                }
                cursor = cursor + CID_HASH_LENGTH;
            }

            // The l field is at the end so we only care about it if we actually want to read it
            if (hint == 0) {
                require(n > 0, "You should not be reading an l value for the node at the tip");
                assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_L_2B);
                cursor = cursor + 2;

                if (bytes1(nodes[n][cursor:cursor + 1]) == CBOR_NULL_1B) {
                    cursor = cursor + 1;
                } else {
                    assert(bytes9(nodes[n][cursor:cursor + 9]) == CID_PREFIX_BYTES_9B);
                    cursor = cursor + 9;

                    // Our 32 bytes
                    bytes32 val = bytes32(nodes[n][cursor:cursor + CID_HASH_LENGTH]);
                    require(val == proveMe, "l val does not match");
                    proveMe = sha256(nodes[n]);
                }
            }
        }

        return (proveMe, rkey);
    }
}
