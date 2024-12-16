// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CBORNavigator} from "./CBORNavigator.sol";
import {console} from "forge-std/console.sol";

bytes1 constant CBOR_NULL_1 = hex"f6";

bytes1 constant CBOR_MAPPING_2_ENTRIES_1 = hex"a2"; // tree node has 2 fields
bytes1 constant CBOR_MAPPING_4_ENTRIES_1 = hex"a4"; // tree node entry field has 4 fields
bytes1 constant CBOR_MAPPING_5_ENTRIES_1 = hex"a5"; // sig node has 5 fields when unsigned
bytes1 constant CBOR_MAPPING_15_ENTRIES_1 = hex"af"; // data node has 4 to 5 fields but they might increase it

// Tree nodes contain e and l
bytes2 constant CBOR_HEADER_E_2 = bytes2(hex"6165");
bytes2 constant CBOR_HEADER_L_2 = bytes2(hex"616c");
bytes3 constant CBOR_HEADER_L_NULL_3 = bytes3(hex"616cf6");

// e contains k, p, t, v
bytes2 constant CBOR_HEADER_K_2 = bytes2(hex"616b");
bytes2 constant CBOR_HEADER_P_2 = bytes2(hex"6170");
bytes2 constant CBOR_HEADER_T_2 = bytes2(hex"6174");
bytes2 constant CBOR_HEADER_V_2 = bytes2(hex"6176");

// signodes contain did, rev, data, prev and version (which must be 3)
bytes4 constant CBOR_HEADER_DID_4 = bytes4(hex"63646964"); // text, did
bytes4 constant CBOR_HEADER_REV_4 = bytes4(hex"63726576"); // text, rev
bytes5 constant CBOR_HEADER_DATA_5 = bytes5(hex"6464617461"); // text, data
bytes5 constant CBOR_HEADER_PREV_5 = bytes5(hex"6470726576"); // text, prev
bytes9 constant CBOR_HEADER_AND_VALUE_VERSION_9_9 = bytes9(hex"6776657273696f6e03"); // text, version, 3

// data nodes contain text (we use a bytes array for this one)
bytes constant CBOR_HEADER_TEXT_5 = bytes(hex"6474657874"); // text, "text"

// CID IDs are 32-byte hashes preceded by some special CBOR tag data then the multibyte prefix
bytes9 constant CID_PREFIX_BYTES_9 = hex"d82a58250001711220"; // CBOR CID header stuff then the length (37)
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

    function _parseMessageCBOR(bytes calldata content) internal pure returns (bytes calldata message) {
        uint256 cursor;

        uint256 payloadStart;
        uint256 payloadEnd;

        // Mapping byte
        // Typically these have 4 or 5 fields (depending whether they are replies).
        // We only care about one field, the text.
        // We'll sanity-check that the range is somewhere from 2 to 15.
        bytes1 mappingByte = bytes1(content[cursor:cursor + 1]);
        assert(uint8(mappingByte) >= uint8(CBOR_MAPPING_2_ENTRIES_1));
        assert(uint8(mappingByte) <= uint8(CBOR_MAPPING_15_ENTRIES_1));
        cursor = 1;

        // Extract the message from the CBOR
        cursor = CBORNavigator.indexOfMappingField(content, CBOR_HEADER_TEXT_5, cursor);
        (payloadStart, payloadEnd,) = CBORNavigator.cborFieldMetaData(content, cursor); // value
        bytes calldata message = content[payloadStart:payloadEnd];
        return message;
    }

    /// @notice Check that the supplied commit node includes the supplied root hash, or revert if it doesn't.
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param commitNode The CBOR-encoded commit node
    function assertCommitNodeContainsData(bytes32 proveMe, bytes calldata commitNode) public pure {
        uint256 cursor;
        uint256 extra;

        assert(bytes1(commitNode[cursor:cursor + 1]) == CBOR_MAPPING_5_ENTRIES_1);
        cursor = 1;

        assert(bytes5(commitNode[cursor:cursor + 4]) == CBOR_HEADER_DID_4);
        cursor = cursor + 4;
        (, cursor,) = CBORNavigator.cborFieldMetaData(commitNode, cursor);

        assert(bytes4(commitNode[cursor:cursor + 4]) == CBOR_HEADER_REV_4);
        cursor = cursor + 4;
        (, cursor,) = CBORNavigator.cborFieldMetaData(commitNode, cursor);

        assert(bytes8(commitNode[cursor:cursor + 5]) == CBOR_HEADER_DATA_5);
        cursor = cursor + 5;
        assert(bytes9(commitNode[cursor:cursor + 9]) == CID_PREFIX_BYTES_9);
        cursor = cursor + 9;
        require(
            bytes32(commitNode[cursor:cursor + CID_HASH_LENGTH]) == proveMe, "Data field does not contain expected hash"
        );
        cursor = cursor + CID_HASH_LENGTH;

        assert(bytes5(commitNode[cursor:cursor + 5]) == CBOR_HEADER_PREV_5);
        cursor = cursor + 5;
        if (bytes1(commitNode[cursor:cursor + 1]) == CBOR_NULL_1) {
            cursor = cursor + 1;
        } else {
            assert(bytes9(commitNode[cursor:cursor + 9]) == CID_PREFIX_BYTES_9);
            cursor = cursor + 9;
            cursor = cursor + CID_HASH_LENGTH; // cid we don't care about
        }

        require(bytes9(commitNode[cursor:cursor + 9]) == CBOR_HEADER_AND_VALUE_VERSION_9_9, "v3 field not found"); // text "version" 3
    }

    /// @notice Verify the path from the hash of the data node provided (index 0) to the final node provided.
    /// @dev The final node is intended to be the root node of the MST tree, but you must verify this by checking the commit node
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param nodes An array of CBOR-encoded tree nodes, each containing an entry for the hash of an earlier one
    /// @return rootNode The final node of the series, intended (but not verified) to be the root node
    /// @return rkey The record key of the data node
    function merkleProvenRootHash(bytes32 proveMe, bytes[] calldata nodes, uint256[] calldata hints)
        public
        pure
        returns (bytes32, string memory)
    {
        string memory rkey;

        uint256 payloadStart;

        // We work up the chain finding the "proveMe" hash in the appropriate place.
        // Each time we find it we hash the current node and use it as the next "proveMe" value to check at the next level up.

        // For the first node (node 0), we need to find the hash we want in the "v" field of one of the entries.
        // However we also need to look at the preceding fields to recover the rkey (see below).
        // For subsequent nodes, we need to find the hash in either the "l" field or the "t" field of one of the entries.

        for (uint256 n = 0; n < nodes.length; n++) {
            // The hints are indexes telling us where we can look to find the data we need for verification.
            // This avoids the need to read data from a lot of entries just to discover that they aren't what we're looking for.
            // The hints could be malicious, but if they are wrong then we will simply not find the data and verification will fail.
            // We use 0 to represent the "l" field of the node.
            // Any other number represents the index of one of the entries, offset by 1.

            uint256 hint = hints[n];

            uint256 numEntries;

            // Entries may have a value, which is extracted from the header, and a payload, which we read as a calldata slice.
            // cborFieldMetaData() will tell us the end of the payload field, so each time we read it we will advance the cursor to it
            // If we know exactly what data we expect to find, eg with a mapping field name, we manually advance the cursor
            uint256 cursor;

            // mapping byte
            assert(bytes1(nodes[n][cursor:cursor + 1]) == CBOR_MAPPING_2_ENTRIES_1);
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
                if (bytes3(nodes[n][lastByte - 3:lastByte]) != bytes3(CBOR_HEADER_L_NULL_3)) {
                    require(bytes32(nodes[n][lastByte - 32:lastByte]) == proveMe, "l value mismatch");
                    require(bytes9(nodes[n][lastByte - 32 - 9:lastByte - 32]) == bytes9(CID_PREFIX_BYTES_9));
                    require(
                        bytes2(nodes[n][lastByte - 32 - 9 - 2:lastByte - 32 - 9]) == CBOR_HEADER_L_2,
                        "l prefix mismatch"
                    );
                    proveMe = sha256(nodes[n]);
                    continue;
                }
            }

            assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_E_2);
            cursor = cursor + 2;
            (cursor, numEntries) = CBORNavigator.countArrayEntries(nodes[n], cursor);

            // If the node is in an "e" entry, we only have to loop as far as the index of the entry we want
            // If the node is in the "l", we'll have to go through them all to find where "l" starts
            require(hint <= numEntries, "Hint is for an index beyond the end of the entries");
            if (hint > 0) {
                numEntries = hint;
            }

            for (uint256 i = 0; i < numEntries; i++) {
                // mapping byte for a mapping with 4 entries
                assert(bytes1(nodes[n][cursor:cursor + 1]) == CBOR_MAPPING_4_ENTRIES_1);
                cursor = cursor + 1;

                // For the first node, which contains information about the skeet, we also need the record key (k) in the relevant entry.
                // Atproto uses a compression scheme where we have to construct it from the k and p of earlier entries.
                // For all later nodes we can ignore the value but we still have to check the field lengths to know how far to advance the cursor.

                if (n == 0) {
                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_K_2);
                    cursor = cursor + 2;

                    (payloadStart, cursor,) = CBORNavigator.cborFieldMetaData(nodes[n], cursor);
                    string memory kval = string(nodes[n][payloadStart:cursor]);

                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_P_2);
                    cursor = cursor + 2;

                    uint64 pval;
                    (, cursor, pval) = CBORNavigator.cborFieldMetaData(nodes[n], cursor); // value

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
                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_K_2);
                    cursor = cursor + 2;

                    // Skip variable-length k
                    (, cursor,) = CBORNavigator.cborFieldMetaData(nodes[n], cursor);

                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_P_2);
                    cursor = cursor + 2;

                    // Skip variable-length p
                    (, cursor,) = CBORNavigator.cborFieldMetaData(nodes[n], cursor); // val
                }

                assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_T_2);
                cursor = cursor + 2;

                if (bytes1(nodes[n][cursor:cursor + 1]) == CBOR_NULL_1) {
                    cursor = cursor + 1;
                } else {
                    assert(bytes9(nodes[n][cursor:cursor + 9]) == CID_PREFIX_BYTES_9);
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
                assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_V_2);
                cursor = cursor + 2;

                assert(bytes9(nodes[n][cursor:cursor + 9]) == CID_PREFIX_BYTES_9);
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
                require(n > 0, "You should not be reading an l value for the data node");
                assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_L_2);
                cursor = cursor + 2;

                if (bytes1(nodes[n][cursor:cursor + 1]) == CBOR_NULL_1) {
                    cursor = cursor + 1;
                } else {
                    assert(bytes9(nodes[n][cursor:cursor + 9]) == CID_PREFIX_BYTES_9);
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
