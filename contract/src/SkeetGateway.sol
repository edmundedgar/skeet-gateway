// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignerSafe} from "../src/SignerSafe.sol";
import {BBS} from "../src/BBS.sol";
import {ReadCbor} from "solidity-cbor/ReadCbor.sol";
import {console} from "forge-std/console.sol";

contract SkeetGateway {
    mapping(address => SignerSafe) public signerSafes;

    event LogCreateSignerSafe(address indexed signer, address indexed signerSafe);

    event LogExecutePayload(address indexed signer, address indexed to, uint256 value, bytes data, string payload);

    //event LogString(string mystr);

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
        //emit LogString(string(result));
        return string(result);
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1("0")) && byteValue <= uint8(bytes1("9"))) {
            return byteValue - uint8(bytes1("0"));
        } else if (byteValue >= uint8(bytes1("a")) && byteValue <= uint8(bytes1("f"))) {
            return 10 + byteValue - uint8(bytes1("a"));
        } else if (byteValue >= uint8(bytes1("A")) && byteValue <= uint8(bytes1("F"))) {
            return 10 + byteValue - uint8(bytes1("A"));
        }
        revert("unreachable");
    }

    function _stringToAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }
        return address(uint160(bytes20(addrBytes)));
    }

    function _parsePayload(string memory _payload) internal pure returns (address, uint256, bytes memory) {
        // TODO: Put back the indexes that tell us where the text starts and ends
        // BEFORE_ADDRESS may be ok but AFTER_CONTENT will depend on the length of the message
        uint256 BEFORE_ADDRESS = 8;
        uint256 AFTER_CONTENT = 67;
        string memory main_part = _substring(_payload, BEFORE_ADDRESS, AFTER_CONTENT);
        address to = _stringToAddress(_substring(main_part, 0, 42));
        string memory message = _substring(main_part, 43, bytes(main_part).length);
        bytes memory data = abi.encodeWithSignature("postMessage(string)", message);
        return (to, 0, data);
    }

    function predictSafeAddress(address _signer) external view returns (address) {
        bytes32 salt = bytes32(uint256(uint160(_signer)));
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(type(SignerSafe).creationCode)));
        return address(uint160(uint256(hash)));
    }

    function predictSafeAddressFromSig(bytes32 sigHash, uint8 _v, bytes32 _r, bytes32 _s)
        external
        view
        returns (address)
    {
        address signer = predictSignerAddressFromSig(sigHash, _v, _r, _s);
        bytes32 salt = bytes32(uint256(uint160(signer)));
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(type(SignerSafe).creationCode)));
        return address(uint160(uint256(hash)));
    }

    function predictSignerAddressFromSig(bytes32 sigHash, uint8 _v, bytes32 _r, bytes32 _s)
        public
        pure
        returns (address)
    {
        return ecrecover(sigHash, _v, _r, _s);
    }

    function assertCommitNodeContainsData(bytes32 proveMe, bytes calldata commitNode) public pure {
        assert(bytes8(commitNode[0:5]) == bytes8(hex"a563646964")); // mapping, text, did
        uint32 cursor = 5;

        uint64 extra;
        (cursor, extra,) = ReadCbor.header(commitNode, cursor); // did content
        cursor = cursor + uint32(extra);

        assert(bytes8(commitNode[cursor:cursor + 4]) == bytes8(hex"63726576")); // text, rev
        cursor = cursor + 4;
        (cursor, extra,) = ReadCbor.header(commitNode, cursor); // did content
        cursor = cursor + uint32(extra);

        assert(bytes8(commitNode[cursor:cursor + 5]) == bytes8(hex"6464617461")); // rev content
        cursor = cursor + 5;

        assert(bytes8(commitNode[cursor:cursor + 4]) == bytes8(hex"d82a5825")); // CBOR CID header stuff then the length (37)
        cursor = cursor + 4;
        assert(bytes8(commitNode[cursor:cursor + 5]) == bytes8(hex"0001711220")); // Multibase header, multicodec might be 55?
        cursor = cursor + 5;
        require(bytes32(commitNode[cursor:cursor + 32]) == proveMe, "Data field does not contain expected hash");
        cursor = cursor + 32;

        assert(bytes8(commitNode[cursor:cursor + 5]) == bytes8(hex"6470726576")); // text, prev
        cursor = cursor + 5;

        if (ReadCbor.isNull(commitNode, cursor)) {
            cursor = cursor + 1;
        } else {
            assert(bytes8(commitNode[cursor:cursor + 4]) == bytes8(hex"d82a5825")); // CBOR CID header stuff then the length (37)
            cursor = cursor + 4;
            //assert(bytes8(commitNode[cursor:cursor+5]) == bytes8(hex"0001711220")); // Multibase header, multicodec might be 55?
            cursor = cursor + 5;
            cursor = cursor + 32; // cid we don't care about
        }

        require(bytes9(commitNode[cursor:cursor + 9]) == bytes9(hex"6776657273696f6e03"), "v3 field not found"); // text "version" 3
    }

    function merkleProvenRootHash(bytes32 proveMe, bytes[] calldata nodes, uint256[] calldata hints)
        public
        pure
        returns (bytes32, string memory)
    {
        string memory rkey;

        for (uint256 n = 0; n < nodes.length; n++) {
            uint64 hint = uint64(hints[n]);

            uint64 nextLen;
            uint64 numEntries;

            assert(bytes8(nodes[n][0:3]) == bytes8(hex"a26165"));
            uint32 cursor = 3; // mapping header, text, e

            // Header for variable-length array
            (cursor, numEntries,) = ReadCbor.header(nodes[n], cursor); // e array header

            require(hint <= numEntries, "Hint is for an index beyond the end of the entries");
            // If the node is in an "e" entry, we only have to loop as far as the index of the entry we want
            // If the node is in the "l", we'll have to go through them all to find where "l" starts
            if (hint > 0) {
                numEntries = hint;
            }

            for (uint256 i = 0; i < numEntries; i++) {
                // For the first node, which is the data node, we also need the record key.
                // For everything else we can go past it

                if (n == 0) {
                    assert(bytes8(nodes[n][cursor:cursor + 3]) == bytes8(hex"a4616b")); // 4 item map, text, k
                    cursor = cursor + 3;

                    (cursor, nextLen,) = ReadCbor.header(nodes[n], cursor); // value
                    string memory kval = string(nodes[n][cursor:cursor + nextLen]);
                    cursor = cursor + uint32(nextLen);

                    // p
                    (cursor, nextLen,) = ReadCbor.header(nodes[n], cursor); // key
                    bytes memory p = nodes[n][cursor:cursor + nextLen];
                    cursor = cursor + uint32(nextLen);

                    // TODO: Check whether this may vary depending on the size of p
                    (, nextLen,) = ReadCbor.header(nodes[n], cursor); // value
                    cursor = cursor + 1;
                    uint8 pval = uint8(nextLen);
                    //cursor = cursor + nextLen; // The cursor is already advanced

                    // Take the first bytes specified by the partial from the existing rkey
                    // Then append the bytes found in kval
                    if (pval == 0) {
                        rkey = kval;
                    } else {
                        string memory oldr = _substring(rkey, 0, uint256(pval));
                        rkey = string.concat(oldr, kval);
                    }
                } else {
                    assert(bytes8(nodes[n][cursor:cursor + 3]) == bytes8(hex"a4616b")); // 4 item map, text, k
                    cursor = cursor + 3;

                    // Variable-length string
                    (cursor, nextLen,) = ReadCbor.header(nodes[n], cursor);
                    cursor = cursor + uint32(nextLen);

                    assert(bytes8(nodes[n][cursor:cursor + 2]) == bytes8(hex"6170")); // text, p
                    cursor = cursor + 2;

                    // For an int the val is in the header so we shouldn't need to advance cursor beyond what parseCborHeader did
                    // TODO: Make sure this works if p > 24 and it needs the extra byte
                    (cursor, nextLen,) = ReadCbor.header(nodes[n], cursor); // val
                }

                assert(bytes8(nodes[n][cursor:cursor + 2]) == bytes8(hex"6174")); // text, t
                cursor = cursor + 2;

                if (ReadCbor.isNull(nodes[n], cursor)) {
                    // TODO: What's the first byte here that's ignored by isNullNext?
                    assert(bytes8(nodes[n][cursor:cursor + 1]) == bytes8(hex"f6")); // null
                    cursor = cursor + 1;
                } else {
                    assert(bytes8(nodes[n][cursor:cursor + 4]) == bytes8(hex"d82a5825")); // CBOR CID header stuff then the length (37)
                    cursor = cursor + 4;

                    assert(bytes8(nodes[n][cursor:cursor + 5]) == bytes8(hex"0001711220")); // Multibase header, multicodec might be 55?
                    cursor = cursor + 5;

                    // Our 32 bytes
                    if (n > 0 && hint > 0 && i == hint - 1) {
                        bytes32 val = bytes32(nodes[n][cursor:cursor + 32]);
                        require(val == proveMe, "Value does not match target");
                        proveMe = sha256(nodes[n]);
                        continue;
                    }

                    cursor = cursor + 32;
                }

                // non-nullable v
                assert(bytes8(nodes[n][cursor:cursor + 2]) == bytes8(hex"6176")); // text, t
                cursor = cursor + 2;
                assert(bytes8(nodes[n][cursor:cursor + 4]) == bytes8(hex"d82a5825")); // CBOR CID header stuff then the length (37)
                cursor = cursor + 4;
                assert(bytes8(nodes[n][cursor:cursor + 5]) == bytes8(hex"0001711220")); // Multibase header, multicodec might be 55?
                cursor = cursor + 5;

                // 32 bytes we only care about if it's the initial data node
                if (n == 0 && i == hint - 1) {
                    // Our 32 bytes
                    bytes32 val = bytes32(nodes[n][cursor:cursor + 32]);
                    require(val == proveMe, "e val does not match");
                    proveMe = sha256(nodes[0]);
                }
                cursor = cursor + 32;
            }

            // The l field is at the end so we only care about it if we actually want to read it
            if (n > 0 && hint == 0) {
                assert(bytes8(nodes[n][cursor:cursor + 2]) == bytes8(hex"616c")); // text, l
                cursor = cursor + 2;

                if (ReadCbor.isNull(nodes[n], cursor)) {
                    // TODO: What's the first byte here that's ignored by isNullNext?
                    assert(bytes8(nodes[n][cursor:cursor + 1]) == bytes8(hex"f6")); // null
                    cursor = cursor + 1;
                } else {
                    assert(bytes8(nodes[n][cursor:cursor + 4]) == bytes8(hex"d82a5825")); // CBOR CID header stuff then the length (37)
                    cursor = cursor + 4;

                    assert(bytes8(nodes[n][cursor:cursor + 5]) == bytes8(hex"0001711220")); // Multibase header, multicodec might be 55?
                    cursor = cursor + 5;

                    // Our 32 bytes
                    bytes32 val = bytes32(nodes[n][cursor:cursor + 32]);
                    require(val == proveMe, "l val does not match");
                    proveMe = sha256(nodes[n]);
                }
            }
        }

        return (proveMe, rkey);
    }

    // Handles a skeet and
    function handleSkeet(
        bytes calldata content,
        bytes[] calldata nodes,
        uint256[] calldata nodeHints,
        bytes calldata commitNode,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        {
            bytes32 target = sha256(abi.encodePacked(content));
            (bytes32 rootHash, string memory rkey) = merkleProvenRootHash(target, nodes, nodeHints);
            // TODO: Check rkey is a post, maybe also store it as a nonce
            assertCommitNodeContainsData(rootHash, commitNode);
        }

        {
            bytes32 commitNodeHash = sha256(abi.encodePacked(commitNode));
            address signer = ecrecover(commitNodeHash, _v, _r, _s);

            executePayload(signer, content);
        }
    }

    function executePayload(address signer, bytes calldata content) internal {
        require(signer != address(0), "Signer should not be empty");
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        (address to, uint256 value, bytes memory payloadData) = _parsePayload(string(content));

        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, value, payloadData, string(content));
    }
}
