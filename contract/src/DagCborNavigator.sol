// SPDX-License-Identifier: MIT
// Based on CBORDecode.sol from filecoin-solidity by Zondax AG (Apache 2.0 license)

import {console} from "forge-std/console.sol";

pragma solidity ^0.8.17;

/// @notice This library provides functions to find data inside DAG-CBOR-encoded calldata
/// @author Edmund Edgar
library DagCborNavigator {
    /// @notice Return the index of the value of the named field inside a mapping
    /// @param cbor encoded mapping content (data must end when the mapping does)
    /// @param fieldHeader The field you want to read
    /// @param cursor Cursor to start at to read the actual data
    /// @return uint256 End of field
    function indexOfMappingField(bytes calldata cbor, bytes memory fieldHeader, uint256 cursor)
        internal
        pure
        returns (uint256)
    {
        uint256 fieldHeaderLength = fieldHeader.length;
        uint256 endIndex = cbor.length - fieldHeaderLength;

        while (cursor < endIndex) {
            if (bytes8(cbor[cursor:cursor + fieldHeaderLength]) == bytes8(fieldHeader)) {
                return cursor + fieldHeaderLength;
            } else {
                // field for the name
                cursor = indexOfFieldPayloadEnd(cbor, cursor);
                // field for the value
                cursor = indexOfFieldPayloadEnd(cbor, cursor);
            }
        }
        revert("fieldHeader not found");
    }

    // Based on the parseCborHeader function from:
    // https://github.com/filecoin-project/filecoin-solidity/blob/master/contracts/v0.8/utils/CborDecode.sol
    // Uses calldata instead of memory copying
    // Adds support for CID tags
    function parseCborHeader(bytes calldata cbor, uint256 byteIndex) internal pure returns (uint8, uint64, uint256) {
        uint8 first = uint8(bytes1(cbor[byteIndex:byteIndex + 1]));
        byteIndex++;

        uint8 maj = first >> 5;
        uint8 low = first & 0x1f;

        uint64 extra;

        if (maj == 6) {
            // Tag
            // https://github.com/ipld/cid-cbor
            // The only supported tag is CID (42), as per
            // https://ipld.io/specs/codecs/dag-cbor/spec/
            // Next bytes must be:
            // 2a: Tag 42
            // 58: CBOR major byte, minor byte
            // 25: 37 bytes coming, including the leading 00
            require(
                bytes3(cbor[byteIndex:byteIndex + 3]) == bytes3(hex"2a5825"),
                "Unsupported tag or unexpected CID header bytes"
            );
            byteIndex += 3;
            return (maj, 37, byteIndex);
        }

        if (low < 24) {
            // extra is lower bits
            extra = low;
        } else if (low == 24) {
            // extra in next byte
            extra = uint8(bytes1(cbor[byteIndex:byteIndex + 1]));
            byteIndex += 1;
        } else if (low == 25) {
            // extra in next 2 bytes
            extra = uint16(bytes2(cbor[byteIndex:byteIndex + 2]));
            byteIndex += 2;
        } else if (low == 26) {
            // extra in next 4 bytes
            extra = uint32(bytes4(cbor[byteIndex:byteIndex + 4]));
            byteIndex += 4;
        } else if (low == 27) {
            // extra in next 8 bytes
            extra = uint64(bytes8(cbor[byteIndex:byteIndex + 8]));
            byteIndex += 8;
        } else {
            // We don't handle CBOR headers with extra > 27, i.e. no indefinite lengths
            revert("cannot handle headers with extra > 27");
        }

        return (maj, extra, byteIndex);
    }

    /// @notice Return end of the field (ie the end of the payload, not just the header)
    /// @param cbor cbor encoded bytes to parse from
    /// @param byteIndex index of the start of the header
    /// @return index where the payload ends
    function indexOfFieldPayloadEnd(bytes calldata cbor, uint256 byteIndex) internal pure returns (uint256) {
        uint8 maj;
        uint64 extra;

        (maj, extra, byteIndex) = parseCborHeader(cbor, byteIndex);

        // Types are divided into "atomic" types 0–1 and 6–7, for which the count field encodes the value directly,
        // and non-atomic types 2–5, for which the count field encodes the size of the following payload field.

        // For string/bytes types, the extra field tells us the length of the payload
        // We also handle CID tags this way (major type 6, the only tags DAG-CBOR supports)
        if (maj == 2 || maj == 3 || maj == 6) {
            return byteIndex + extra;
        }

        if (maj == 0 || maj == 1 || maj == 7) {
            return byteIndex;
        }

        // For a mapping or an array, the payload length is the combined length of all the entries
        // The entries may in turn contain their own arrays and maps
        // This can recurse as deep as it likes through layers of nested maps/arrays until you run out of gas
        if (maj == 4 || maj == 5) {
            // For a map the number of entries is doubled because there's a key and a value per item
            uint64 numEntries = (maj == 5) ? extra * 2 : extra;
            for (uint64 i = 0; i < numEntries; i++) {
                byteIndex = indexOfFieldPayloadEnd(cbor, byteIndex);
            }
            return byteIndex;
        }

        revert("Unsupported major type");
    }
}
