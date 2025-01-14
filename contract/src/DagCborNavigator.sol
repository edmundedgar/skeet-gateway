// SPDX-License-Identifier: MIT
// Based on CBORDecode.sol from filecoin-solidity by Zondax AG (Apache 2.0 license)

import {console} from "forge-std/console.sol";

pragma solidity ^0.8.28;

/// @notice This library provides functions to find data inside DAG-CBOR-encoded calldata
/// @author Edmund Edgar
library DagCborNavigator {
    // Each level in the tree gets a selector consisting of a key/index (which may be empty to try all),
    //  mapping text: "oink" | array 3: "oink"

    enum ValueMatch {
        Any,
        Exact,
        Prefix
    }

    struct DagCborSelector {
        string fieldName; // The field we should match (unless you set isKeyAny)
        uint256 arrayIndex; // The array index we should match (unless you set isKeyAny)
        bytes fieldValue; // The field value we should match (unless you set ValueMatch.Any)
        bool isKeyAny; // Whether we should match any mapping field / array index
        ValueMatch valueMatch; // Whether we should match any value
        bool unpackValue; // Should we return the whole field including the header, or its value
    }

    function createTargetSelector(string memory fieldName) external pure returns (DagCborSelector memory) {
        return DagCborSelector(fieldName, 0, bytes(hex""), false, ValueMatch.Any, true);
    }

    function createSelector(string memory fieldName) external pure returns (DagCborSelector memory) {
        return DagCborSelector(fieldName, 0, bytes(hex""), false, ValueMatch.Any, false);
    }

    function createSelector(uint256 idx) external pure returns (DagCborSelector memory) {
        return DagCborSelector("", idx, bytes(hex""), false, ValueMatch.Any, false);
    }

    function createSelector() external pure returns (DagCborSelector memory) {
        return DagCborSelector("", 0, bytes(hex""), true, ValueMatch.Any, false);
    }

    function createSelector(uint256 idx, bytes memory fieldValue) external pure returns (DagCborSelector memory) {
        return DagCborSelector("", idx, fieldValue, false, ValueMatch.Exact, false);
    }

    function createSelector(string memory fieldName, string memory fieldValue)
        external
        pure
        returns (DagCborSelector memory)
    {
        return DagCborSelector(fieldName, 0, bytes(fieldValue), false, ValueMatch.Exact, false);
    }

    // Runs through nested arrays and mappings in cbor and finds the first entry matching the selector, then returns its start and end
    // If not found, start will return 0 and end will return the cursor where it ended up
    function firstMatch(bytes calldata cbor, DagCborSelector[] memory selectors, uint256 currentLevel, uint256 cursor)
        public
        returns (uint256, uint256)
    {
        uint64 extra;

        // Initialize at zero when the user calls us, then decrease each time and return when we hit 1
        if (currentLevel == 0) {
            currentLevel = selectors.length;
        }

        DagCborSelector memory sel = selectors[currentLevel - 1];
        uint8 maj;
        uint256 numEntries;

        // 0 means not found
        // (it cannot be 0 if found because of the mapping/array header)
        uint256 fieldStart;

        (maj, numEntries, cursor) = parseCborHeader(cbor, cursor);
        if (maj == 5) {
            for (uint256 mf = 0; mf < numEntries; mf++) {
                // Read the key
                (, extra, cursor) = parseCborHeader(cbor, cursor);
                if (
                    sel.isKeyAny
                        || (
                            extra == bytes(sel.fieldName).length
                                && keccak256(cbor[cursor:cursor + extra]) == keccak256(bytes(sel.fieldName))
                        )
                ) {
                    cursor = cursor + extra; // Advance to the end of the key
                    // Found the field for this mapping.
                    // Now see if the value passes our selector
                    // Stash the cursor in fieldStart in case we find it
                    // We won't return fieldStart unless we do
                    fieldStart = cursor;
                    (maj, extra, cursor) = parseCborHeader(cbor, cursor);
                    if (
                        sel.valueMatch == ValueMatch.Any
                            || (
                                sel.valueMatch == ValueMatch.Exact && extra == bytes(sel.fieldValue).length
                                    && keccak256(cbor[cursor:cursor + extra]) == keccak256(bytes(sel.fieldValue))
                            )
                            || (
                                sel.valueMatch == ValueMatch.Prefix && extra >= bytes(sel.fieldValue).length
                                    && keccak256(cbor[cursor:cursor + bytes(sel.fieldValue).length])
                                        == keccak256(bytes(sel.fieldValue))
                            )
                    ) {
                        if (currentLevel == 1) {
                            // got to the bottom and this is our value
                            // TODO: Handle if this is an int and we want the extra
                            if (sel.unpackValue) {
                                if (maj == 2 || maj == 3 || maj == 6) {
                                    return (cursor, cursor + extra);
                                } else {
                                    return (cursor, extra);
                                }
                            } else {
                                return (fieldStart, cursor + extra);
                            }
                        } else {
                            // require(maj == 4 || maj == 5, "Can only recurse into an array or mapping");
                            // got a match but we have more levels to try, so try the next match with this level removed
                            (fieldStart, cursor) = firstMatch(cbor, selectors, currentLevel - 1, fieldStart);
                            if (fieldStart > 0) {
                                return (fieldStart, cursor);
                            }
                        }
                    } else {
                        cursor = fieldEnd(cbor, cursor);
                    }
                } else {
                    // Not the field yet, keep going
                    cursor = cursor + extra; // Advance to the end of the key
                    cursor = fieldEnd(cbor, cursor);
                }
            }
        } else if (maj == 4) {
            if (!sel.isKeyAny && sel.arrayIndex > numEntries) {
                return (0, cursor);
            }
            for (uint256 mf = 0; mf < numEntries; mf++) {
                fieldStart = cursor;
                if (sel.isKeyAny || sel.arrayIndex == mf) {
                    (maj, extra, cursor) = parseCborHeader(cbor, cursor); // TODO: handle if this is an int
                    if (
                        sel.valueMatch == ValueMatch.Any
                            || (
                                sel.valueMatch == ValueMatch.Exact && extra == bytes(sel.fieldValue).length
                                    && keccak256(cbor[cursor:cursor + extra]) == keccak256(bytes(sel.fieldValue))
                            )
                            || (
                                sel.valueMatch == ValueMatch.Prefix && extra >= bytes(sel.fieldValue).length
                                    && keccak256(cbor[cursor:cursor + bytes(sel.fieldValue).length])
                                        == keccak256(bytes(sel.fieldValue))
                            )
                    ) {
                        if (currentLevel == 1) {
                            return (fieldStart, cursor + extra);
                        } else {
                            // require(maj == 4 || maj == 5, "Can only recurse into an array or mapping");
                            // got a match but we have more levels to try, so try the next match with this level removed
                            (fieldStart, cursor) = firstMatch(cbor, selectors, currentLevel - 1, fieldStart);
                            if (fieldStart > 0) {
                                return (fieldStart, cursor);
                            }
                        }
                    }
                }
                // If the key didn't match, jump to the end of the field, recursively if it's an arary
                cursor = fieldEnd(cbor, cursor);
            }
        }
        return (0, cursor);
    }

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
            if (keccak256(cbor[cursor:cursor + fieldHeaderLength]) == keccak256(fieldHeader)) {
                return cursor + fieldHeaderLength;
            } else {
                // field for the name
                cursor = fieldEnd(cbor, cursor);
                // field for the value
                cursor = fieldEnd(cbor, cursor);
            }
        }
        revert("fieldHeader not found");
    }

    /// @notice Return the index where a field with this header should be added to the CBOR
    /// @dev We use this when we have cbor with "sig" stripped and we need to put it back to hash the data
    /// @dev This is similar to indexOfMappingField about except that it's for adding a field so:
    /// @dev   1) It returns the index of the field after the specified one in dag-cbor key sort order
    /// @dev   2) It returns the start of the name field not the value field
    /// @dev   3) If it reaches the end of the cbor it gives you the end index instead of reverting
    /// @param cbor encoded mapping content (data must end when the mapping does)
    /// @param fieldHeader The field you want to insert
    /// @param cursor Cursor to start at to read the actual data
    /// @return uint256 Start of the field
    function indexToInsertMappingField(bytes calldata cbor, bytes memory fieldHeader, uint256 cursor)
        internal
        pure
        returns (uint256)
    {
        uint256 fieldHeaderLength = fieldHeader.length;

        // at 23 bytes the cbor name header needs 2 bytes which would need extra tests
        // (but should Just Work)
        // 23 bytes should be enough for anyone
        require(fieldHeaderLength < 24, "field too long");

        uint256 endIndex = cbor.length - fieldHeaderLength;

        while (cursor < endIndex) {
            if (uint256(bytes32(cbor[cursor:cursor + fieldHeaderLength])) > uint256(bytes32(fieldHeader))) {
                return cursor;
            } else {
                // field for the name
                cursor = fieldEnd(cbor, cursor);
                // field for the value
                cursor = fieldEnd(cbor, cursor);
            }
        }
        return cursor;
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

    /// @notice Return the value of an atomic type (ie one with no payload)
    /// @dev Will revert if called on a non-atomic field type
    /// @param cbor cbor encoded bytes to parse from
    /// @param cursor index of the start of the header
    /// @return The value found in the header
    /// @return end of header, ie position of the start of the first entry
    function fieldValue(bytes calldata cbor, uint256 cursor) internal pure returns (uint64, uint256) {
        uint8 maj;
        uint64 extra;
        (maj, extra, cursor) = parseCborHeader(cbor, cursor);

        if (maj == 0) {
            return (extra, cursor);
        }

        if (maj == 1) {
            revert("major type 1 not supported");
        }

        if (maj == 7) {
            revert("major type 7 not supported");
        }

        revert("Non-atomic, use fieldPayloadStart");
    }

    /// @notice Return the number of entries in the array or mapping
    /// @dev Will revert if called on a field that isn't an array or mapping
    /// @param cbor cbor encoded bytes to parse from
    /// @param cursor index of the start of the header
    /// @return number of entries
    /// @return end of header, ie position of the start of the first entry
    function fieldEntryCount(bytes calldata cbor, uint256 cursor) internal pure returns (uint64, uint256) {
        uint8 maj;
        uint64 extra;
        (maj, extra, cursor) = parseCborHeader(cbor, cursor);

        require(maj == 4 || maj == 5, "Not array or mapping");

        return (extra, cursor);
    }

    /// @notice Return start of the field payload (after the header) and the cursor for the end
    /// @dev Will revert if called on a type of field with no payload
    /// @param cbor cbor encoded bytes to parse from
    /// @param cursor index of the start of the header
    /// @return start of payload
    /// @return end of payload
    function fieldPayloadStart(bytes calldata cbor, uint256 cursor) internal pure returns (uint256, uint256) {
        uint8 maj;
        uint64 extra;
        (maj, extra, cursor) = parseCborHeader(cbor, cursor);

        //        require(maj == 2 || maj == 3 || maj == 6, "atomic type, no payload");
        return (cursor, cursor + extra);
    }

    /// @notice Return end of the field (ie the end of the payload, not just the header)
    /// @param cbor cbor encoded bytes to parse from
    /// @param cursor index of the start of the header
    /// @return index where the payload ends
    function fieldEnd(bytes calldata cbor, uint256 cursor) internal pure returns (uint256) {
        uint8 maj;
        uint64 extra;

        (maj, extra, cursor) = parseCborHeader(cbor, cursor);

        // Types are divided into "atomic" types 0–1 and 6–7, for which the count field encodes the value directly,
        // and non-atomic types 2–5, for which the count field encodes the size of the following payload field.

        // For string/bytes types, the extra field tells us the length of the payload
        // We also handle CID tags this way (major type 6, the only tags DAG-CBOR supports)
        if (maj == 2 || maj == 3 || maj == 6) {
            return cursor + extra;
        }

        if (maj == 0 || maj == 1 || maj == 7) {
            return cursor;
        }

        // For a mapping or an array, the payload length is the combined length of all the entries
        // The entries may in turn contain their own arrays and maps
        // This can recurse as deep as it likes through layers of nested maps/arrays until you run out of gas
        if (maj == 4 || maj == 5) {
            // For a map the number of entries is doubled because there's a key and a value per item
            uint64 numEntries = (maj == 5) ? extra * 2 : extra;
            for (uint64 i = 0; i < numEntries; i++) {
                cursor = fieldEnd(cbor, cursor);
            }
            return cursor;
        }

        revert("Unsupported major type");
    }
}
