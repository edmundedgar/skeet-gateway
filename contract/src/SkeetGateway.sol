// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignerSafe} from "../src/SignerSafe.sol";
import {IMessageParser} from "../src/IMessageParser.sol";
import {CBORDecoder} from "./CBORDecoder.sol";
import {console} from "forge-std/console.sol";

contract SkeetGateway {
    struct Bot {
        string domain;
        string subdomain;
        address parser;
    }

    address owner; // Address that can add domains

    mapping(address => SignerSafe) public signerSafes;

    mapping(bytes32 => address) public domainOwners;
    mapping(bytes32 => Bot) public bots;

    event LogCreateSignerSafe(address indexed signer, address indexed signerSafe);

    event LogExecutePayload(address indexed signer, address indexed to, uint256 value, bytes data, string payload);

    constructor() {
        owner = msg.sender;
    }

    function addDomain(string calldata domain, address domainOwner) external {
        require(msg.sender == owner, "Only the owner can add domains");
        domainOwners[keccak256(abi.encodePacked(domain))] = domainOwner;
    }

    function addBot(string calldata subdomain, string calldata domain, address parser) external {
        require(msg.sender == domainOwners[keccak256(abi.encodePacked(domain))], "Not your domain");
        require(parser != address(0), "Address not specified");
        bytes32 key = keccak256(abi.encodePacked(string.concat(string.concat(subdomain, "."), domain)));
        require(address(bots[key].parser) == address(0), "Subdomain already registered");
        bots[key] = Bot(domain, subdomain, parser);
    }

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

    function _parsePayload(bytes calldata content, uint8 botNameLength)
        internal
        view
        returns (address, uint256 value, bytes memory)
    {
        // Extract the message from the CBOR
        assert(bytes5(content[1:6]) == bytes5(hex"6474657874")); // text, "text"
        uint256 nextLen;
        uint256 cursor;
        (, nextLen, cursor) = CBORDecoder.parseCborHeader(content, 6); // value

        require(bytes1(content[cursor:cursor + 1]) == bytes1(hex"40"), "Message should begin with @");

        bytes calldata message = content[cursor:cursor + nextLen];

        // Look up the bot name which should be in the first <256 bytes of the message followed by a space
        address bot = bots[keccak256(message[1:1 + botNameLength])].parser;
        require(address(bot) != address(0), "Bot not found");
        require(bytes1(message[1 + botNameLength:1 + botNameLength + 1]) == bytes1(hex"20"), "No space after bot name");

        return IMessageParser(bot).parseMessage(message[1 + botNameLength + 1:]);
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
        uint256 cursor = 5;

        uint256 extra;
        (, extra, cursor) = CBORDecoder.parseCborHeader(commitNode, cursor); // did content
        cursor = cursor + extra;

        assert(bytes8(commitNode[cursor:cursor + 4]) == bytes8(hex"63726576")); // text, rev
        cursor = cursor + 4;
        (, extra, cursor) = CBORDecoder.parseCborHeader(commitNode, cursor); // did content
        cursor = cursor + extra;

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

        if (CBORDecoder.isNullNext(commitNode, cursor)) {
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
            uint256 hint = hints[n];

            uint256 nextLen;
            uint256 numEntries;

            assert(bytes8(nodes[n][0:3]) == bytes8(hex"a26165"));
            uint256 cursor = 3; // mapping header, text, e

            // Header for variable-length array
            (, numEntries, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor); // e array header

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

                    (, nextLen, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor); // value
                    string memory kval = string(nodes[n][cursor:cursor + nextLen]);
                    cursor = cursor + nextLen;

                    // p
                    (, nextLen, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor); // key
                    bytes memory p = nodes[n][cursor:cursor + nextLen];
                    cursor = cursor + nextLen;

                    // TODO: Check whether this may vary depending on the size of p
                    (, nextLen,) = CBORDecoder.parseCborHeader(nodes[n], cursor); // value
                    cursor = cursor + 1;
                    uint8 pval = uint8(nextLen);
                    if (pval >= 24) {
                        cursor = cursor + 1;
                    }
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
                    (, nextLen, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor);
                    cursor = cursor + nextLen;

                    assert(bytes8(nodes[n][cursor:cursor + 2]) == bytes8(hex"6170")); // text, p
                    cursor = cursor + 2;

                    // For an int the val is in the header so we shouldn't need to advance cursor beyond what parseCborHeader did
                    // TODO: Make sure this works if p > 24 and it needs the extra byte
                    (, nextLen, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor); // val
                }

                assert(bytes8(nodes[n][cursor:cursor + 2]) == bytes8(hex"6174")); // text, t
                cursor = cursor + 2;

                if (CBORDecoder.isNullNext(nodes[n], cursor)) {
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

                if (CBORDecoder.isNullNext(nodes[n], cursor)) {
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
        uint8 botNameLength,
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
            require(bytes18(bytes(rkey)) == bytes18(bytes("app.bsky.feed.post")), "record key did not show a post");
            assertCommitNodeContainsData(rootHash, commitNode);
        }

        {
            bytes32 commitNodeHash = sha256(abi.encodePacked(commitNode));
            address signer = ecrecover(commitNodeHash, _v, _r, _s);

            executePayload(signer, content, botNameLength);
        }
    }

    function executePayload(address signer, bytes calldata content, uint8 botNameLength) internal {
        require(signer != address(0), "Signer should not be empty");
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        (address to, uint256 value, bytes memory payloadData) = _parsePayload(content, botNameLength);

        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, 0, payloadData, string(content));
    }
}
