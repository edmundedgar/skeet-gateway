// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Contract to extract DAG-CBOR-encoded Atproto Merkle Search Tree data
// https://atproto.com/specs/repository
// https://ipld.io/specs/codecs/dag-cbor/spec/

// The order of keys is fixed as per the DAG-CBOR spec.
// Most data is encoded in mappings with a known, fixed-width name field followed by a field of known length.
// We use DagCborNavigator helpers to assert the name field and advance the cursor.
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

import {DagCborNavigator, CID_PREFIX_BYTES_9B} from "./DagCborNavigator.sol";
import {console} from "forge-std/console.sol";

bytes1 constant CBOR_NULL_1B = hex"f6";

// CBOR mappings are encoded with the following initial bytes, indicating the number of entries:
bytes1 constant CBOR_MAPPING_2_ENTRIES_1B = hex"a2"; // used in range check for content mappings
bytes1 constant CBOR_MAPPING_15_ENTRIES_1B = hex"af"; // used in range check for content mappings

// Used only in the fast-path tail-read of the "l" field (reading backwards, helpers don't apply)
bytes2 constant CBOR_HEADER_L_2B = bytes2(hex"616c");
bytes3 constant CBOR_HEADER_L_NULL_3B = bytes3(hex"616cf6"); // l followed by a null

// Combined field+value constant for the version=3 check (field name and value in one read)
bytes9 constant CBOR_HEADER_AND_VALUE_VERSION_3_9B = bytes9(hex"6776657273696f6e03"); // text, version, 3

// content cbor contains text
bytes5 constant CBOR_HEADER_TEXT_5B = bytes5(hex"6474657874"); // text, "text"

// CID IDs are 32-byte hashes which we will find preceded by some special CBOR tag data then the multibyte prefix
uint256 constant CID_HASH_LENGTH = 32;

bytes18 constant APP_BSKY_FEED_POST = bytes18(bytes("app.bsky.feed.post"));

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
    /// @return did a bytes32 representing the DID the signer claims to have (they may be lying)
    function processCommitNode(bytes32 proveMe, bytes calldata commitNode) public pure returns (bytes32) {
        uint256 cursor;
        uint256 extra;

        bytes32 did;

        // The unsigned commit node has 5 entries.
        // A 6th entry, "sig", is added later by hashing the unsigned, 5-entry version.
        cursor = DagCborNavigator.expectCBORMapping(commitNode, cursor, 5);

        cursor = DagCborNavigator.expectCBORTextField3(commitNode, cursor, "did");
        (, extra, cursor) = DagCborNavigator.parseCborHeader(commitNode, cursor);
        did = bytes32(commitNode[cursor:cursor + extra]);
        cursor = cursor + extra;

        cursor = DagCborNavigator.expectCBORTextField3(commitNode, cursor, "rev");
        cursor = DagCborNavigator.ignoreCBORString(commitNode, cursor);

        cursor = DagCborNavigator.expectCBORTextField4(commitNode, cursor, "data");
        cursor = DagCborNavigator.expectCBORCIDPrefix(commitNode, cursor);
        require(
            bytes32(commitNode[cursor:cursor + CID_HASH_LENGTH]) == proveMe, "Data field does not contain expected hash"
        );
        cursor = cursor + CID_HASH_LENGTH;

        cursor = DagCborNavigator.expectCBORTextField4(commitNode, cursor, "prev");
        cursor = DagCborNavigator.ignoreCBORNullableCID(commitNode, cursor);

        require(bytes9(commitNode[cursor:cursor + 9]) == CBOR_HEADER_AND_VALUE_VERSION_3_9B, "v3 field not found"); // text "version" 3
        return did;
    }

    /// @notice Verify the path from the hash of the node provided (index 0) up towards the root, to the final node provided.
    /// @dev The final node is intended to be the root node of the MST tree, but you must verify this by checking the signed commit node
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param nodes An array of CBOR-encoded tree nodes, each containing an entry for the hash of an earlier one
    /// @return rootNode The final node of the series, intended (but not verified) to be the root node
    function merkleProvenRootHash(bytes32 proveMe, bytes[] calldata nodes, uint256[] calldata hints)
        public
        pure
        returns (bytes32)
    {
        // hints: 0 means the target is in the l field; any other value n means it's in the v/t field of entry n (1-based).
        // We work up the chain. Each time we find proveMe we hash the current node and use that as the next proveMe.
        string memory rkey;
	(proveMe, rkey) = _verifyDataNode(nodes[0], hints[0], proveMe);
        require(bytes18(bytes(rkey)) == APP_BSKY_FEED_POST, "record key did not show a post");
        for (uint256 n = 1; n < nodes.length; n++) {
            proveMe = _verifyInnerNode(nodes[n], hints[n], proveMe);
        }
        return proveMe;
    }

    /// @notice Verify an inner node (n > 0).
    /// @dev hint == 0: target is in the l field. Tries a fast path reading from the tail of the node
    ///      to avoid looping through all entries; falls back to a full traversal when l is null,
    ///      because null bytes could appear by coincidence inside a CID hash.
    ///      hint > 0: target is in the t field of entry hint-1.
    function _verifyInnerNode(bytes calldata node, uint256 hint, bytes32 proveMe)
        internal
        pure
        returns (bytes32)
    {
        if (hint == 0) {
            uint256 lastByte = node.length;
            if (bytes3(node[lastByte - 3:lastByte]) != bytes3(CBOR_HEADER_L_NULL_3B)) {
                require(bytes32(node[lastByte - 32:lastByte]) == proveMe, "l value mismatch");
                require(bytes9(node[lastByte - 32 - 9:lastByte - 32]) == bytes9(CID_PREFIX_BYTES_9B), "Unexpected CID prefix");
                require(bytes2(node[lastByte - 32 - 9 - 2:lastByte - 32 - 9]) == CBOR_HEADER_L_2B, "l prefix mismatch");
                return sha256(node);
            }
        }

        uint256 cursor;

        cursor = DagCborNavigator.expectCBORMapping(node, cursor, 2);
        cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "e");

        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(node, cursor);
        require(hint <= numEntries, "Hint is for an index beyond the end of the entries");

        uint256 entriesToLoop = (hint > 0) ? hint : numEntries;
        for (uint256 i = 0; i < entriesToLoop; i++) {
            cursor = DagCborNavigator.expectCBORMapping(node, cursor, 4);

            cursor = cursor + 2; // "k" field name
            cursor = DagCborNavigator.ignoreCBORString(node, cursor);

            cursor = cursor + 2; // "p" field name
            cursor = DagCborNavigator.ignoreCBORInteger(node, cursor);

            cursor = cursor + 2; // "t" field name
            if (bytes1(node[cursor:cursor + 1]) == CBOR_NULL_1B) {
                cursor = cursor + 1;
            } else {
                cursor = DagCborNavigator.expectCBORCIDPrefix(node, cursor);
                if (hint > 0 && i == hint - 1) {
                    require(bytes32(node[cursor:cursor + CID_HASH_LENGTH]) == proveMe, "Value does not match target");
                    return sha256(node);
                }
                cursor = cursor + CID_HASH_LENGTH;
            }

            cursor = cursor + 2; // "v" field name
            cursor = DagCborNavigator.ignoreCBORCID(node, cursor);
        }

        // hint == 0: looped through all entries to reach l, which is null (fast path handled non-null)
        if (hint == 0) {
            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "l");
            cursor = cursor + 1; // null byte
        }
        return proveMe;
    }

    /// @notice Verify the data node (node 0): reconstruct the record key from k/p fields and verify
    ///         proveMe appears in the v field of the entry at hint (1-based index).
    /// @return newProveMe sha256(node)
    /// @return rkey The fully reconstructed ATProto record key up to and including the winning entry
    function _verifyDataNode(bytes calldata node, uint256 hint, bytes32 proveMe)
        internal
        pure
        returns (bytes32, string memory)
    {
        uint256 extra;
        uint256 cursor;
        string memory rkey;

        cursor = DagCborNavigator.expectCBORMapping(node, cursor, 2);
        cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "e");

        uint256 numEntries;
        (, numEntries, cursor) = DagCborNavigator.parseCborHeader(node, cursor);
        require(hint <= numEntries, "Hint is for an index beyond the end of the entries");

        // Compression scheme: each entry's k/p pair extends the running rkey.
        // p is the number of bytes to keep from the current rkey; k is the suffix to append.
        for (uint256 i = 0; i < hint; i++) {
            cursor = DagCborNavigator.expectCBORMapping(node, cursor, 4);

            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "k");
            string memory kval;
            (kval, cursor) = DagCborNavigator.extractCBORString(node, cursor);

            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "p");
            (extra, cursor) = DagCborNavigator.extractCBORInteger(node, cursor);
            if (extra == 0) {
                rkey = kval;
            } else {
                rkey = string.concat(_substring(rkey, 0, uint256(extra)), kval);
            }

            cursor = cursor + 2; // "t" field name
            cursor = DagCborNavigator.ignoreCBORNullableCID(node, cursor);

            cursor = cursor + 2; // "v" field name
            cursor = cursor + 9; // CID prefix

            if (i == hint - 1) {
                require(bytes32(node[cursor:cursor + CID_HASH_LENGTH]) == proveMe, "e val does not match");
                return (sha256(node), rkey);
            }
            cursor = cursor + CID_HASH_LENGTH;
        }
        revert("Target entry not found in data node");
    }

}
