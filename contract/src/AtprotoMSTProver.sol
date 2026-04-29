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

// CBOR mappings are encoded with the following initial bytes, indicating the number of entries:
bytes1 constant CBOR_MAPPING_2_ENTRIES_1B = hex"a2"; // used in range check for content mappings
bytes1 constant CBOR_MAPPING_15_ENTRIES_1B = hex"af"; // used in range check for content mappings

// Combined field+value constant for the version=3 check (field name and value in one read)
bytes9 constant CBOR_HEADER_AND_VALUE_VERSION_3_9B = bytes9(hex"6776657273696f6e03"); // text, version, 3

// content cbor contains text
bytes5 constant CBOR_HEADER_TEXT_5B = bytes5(hex"6474657874"); // text, "text"

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
    function processCommitNode(bytes32 proveMe, bytes calldata commitNode) public pure returns (string memory) {
        uint256 cursor;
        string memory did;

        // The unsigned commit node has 5 entries.
        // A 6th entry, "sig", is added later by hashing the unsigned, 5-entry version.
        cursor = DagCborNavigator.expectCBORMapping(commitNode, cursor, 5);

        cursor = DagCborNavigator.expectCBORTextField3(commitNode, cursor, "did");
        (did, cursor) = DagCborNavigator.extractCBORString(commitNode, cursor);

        cursor = DagCborNavigator.expectCBORTextField3(commitNode, cursor, "rev");
        cursor = DagCborNavigator.ignoreCBORString(commitNode, cursor);

        bytes32 foundCid;
        cursor = DagCborNavigator.expectCBORTextField4(commitNode, cursor, "data");
        (foundCid, cursor) = DagCborNavigator.extractCBORCID(commitNode, cursor);
        require(foundCid == proveMe, "Data field does not contain expected hash");

        cursor = DagCborNavigator.expectCBORTextField4(commitNode, cursor, "prev");
        cursor = DagCborNavigator.ignoreCBORNullableCID(commitNode, cursor);

        cursor = DagCborNavigator.expectCBORTextField7(commitNode, cursor, "version");
        cursor = DagCborNavigator.expectCBORInteger(commitNode, cursor, 3);
        //require(bytes9(commitNode[cursor:cursor + 9]) == CBOR_HEADER_AND_VALUE_VERSION_3_9B, "v3 field not found"); // text "version" 3

        return did;
    }

    /// @notice Verify the path from the hash of the node provided (index 0) up towards the root, to the final node provided.
    /// @dev The final node is intended to be the root node of the MST tree, but you must verify this by checking the signed commit node
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param nodes An array of CBOR-encoded tree nodes, each containing an entry for the hash of an earlier one
    /// @return rootNode The final node of the series, intended (but not verified) to be the root node
    function merkleProvenRootHash(bytes32 proveMe, bytes[] calldata nodes)
        public
        pure
        returns (bytes32)
    {
        for (uint256 n = 1; n < nodes.length; n++) {
            proveMe = _verifyTreeNode(nodes[n], proveMe);
        }
        return proveMe;
    }

    function _verifyTreeNode(bytes calldata node, bytes32 proveMe)
        internal
        pure
        returns (bytes32)
    {
        uint256 cursor;

        cursor = DagCborNavigator.expectCBORMapping(node, cursor, 2);
        cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "e");

        uint256 numEntries;
        (numEntries, cursor) = DagCborNavigator.extractCBORArrayLength(node, cursor);

        for (uint256 i = 0; i < numEntries; i++) {
            cursor = DagCborNavigator.expectCBORMapping(node, cursor, 4);

            cursor = DagCborNavigator.ignoreCBORTextField1(cursor); // "k"
            cursor = DagCborNavigator.ignoreCBORBytes(node, cursor);

            cursor = DagCborNavigator.ignoreCBORTextField1(cursor); // "p"
            cursor = DagCborNavigator.ignoreCBORInteger(node, cursor);

            cursor = DagCborNavigator.ignoreCBORTextField1(cursor); // "t"
            bytes32 tCid;
            (tCid, cursor) = DagCborNavigator.extractCBORNullableCID(node, cursor);
            if (tCid == proveMe) {
                return sha256(node);
            }

            cursor = DagCborNavigator.ignoreCBORTextField1(cursor); // "v"
            cursor = DagCborNavigator.ignoreCBORCID(node, cursor);
        }

        bytes32 foundCid;
        cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "l");
        (foundCid, cursor) = DagCborNavigator.extractCBORCID(node, cursor);
        require(foundCid == proveMe, "Value does not match target");
        return sha256(node);
    }

    /// @notice Verify the data node (node 0): reconstruct the record key from k/p fields and verify
    ///         proveMe appears in some v field.
    /// @return newProveMe sha256(node)
    /// @return rkey The fully reconstructed ATProto record key of the matching entry
    function verifyDataNode(bytes calldata node, bytes32 proveMe)
        public
        pure
        returns (bytes32, string memory)
    {
        uint256 cursor;
        string memory rkey;

        cursor = DagCborNavigator.expectCBORMapping(node, cursor, 2);
        cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "e");

        uint256 numEntries;
        (numEntries, cursor) = DagCborNavigator.extractCBORArrayLength(node, cursor);

        // Compression scheme: each entry's k/p pair extends the running rkey.
        // p is the number of bytes to keep from the current rkey; k is the suffix to append.
        for (uint256 i = 0; i < numEntries; i++) {
            cursor = DagCborNavigator.expectCBORMapping(node, cursor, 4);

            string memory kval;
            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "k");
            (kval, cursor) = DagCborNavigator.extractCBORBytes(node, cursor);

            uint256 bytesReused;
            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "p");
            (bytesReused, cursor) = DagCborNavigator.extractCBORInteger(node, cursor);
            if (bytesReused == 0) {
                rkey = kval;
            } else {
                rkey = string.concat(_substring(rkey, 0, uint256(bytesReused)), kval);
            }

            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "t");
            cursor = DagCborNavigator.ignoreCBORNullableCID(node, cursor);

            cursor = DagCborNavigator.expectCBORTextField1(node, cursor, "v");
            bytes32 foundCid;
            (foundCid, cursor) = DagCborNavigator.extractCBORCID(node, cursor);
            if (foundCid == proveMe) {
                return (sha256(node), rkey);
            }
        }
        revert("Target entry not found in data node");
    }

}
