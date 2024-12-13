// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignerSafe} from "../src/SignerSafe.sol";
import {IMessageParser} from "../src/IMessageParser.sol";
import {CBORDecoder} from "./CBORDecoder.sol";
import {console} from "forge-std/console.sol";

bytes1 constant CBOR_NULL_1 = hex"f6";

// Tree nodes contain e and l
bytes2 constant CBOR_HEADER_E_2 = bytes2(hex"6165");
bytes2 constant CBOR_HEADER_L_2 = bytes2(hex"616c");

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

// data nodes contain text
bytes5 constant CBOR_HEADER_TEXT_5 = bytes5(hex"6474657874"); // text, "text"

// CID IDs are 32-byte hashes preceded by some special CBOR tag data then the multibyte prefix
bytes9 constant CID_PREFIX_BYTES_9 = hex"d82a58250001711220"; // CBOR CID header stuff then the length (37)
uint256 constant CID_HASH_LENGTH = 32;

contract SkeetGateway {
    // Skeets are addressed to a username, eg bbs.bots.example.com
    // The username will be mapped to a contract which translate text into a contract address and transaction code.
    struct Bot {
        string domain;
        string subdomain;
        address parser;
    }

    mapping(bytes32 => Bot) public bots;

    // The owner has only one single privileged role, the ability to add a domain and assign it to an administrator.
    // If you own a domain, you have the ability to register bots under that domain.
    address owner;
    mapping(bytes32 => address) public domainOwners;

    // We maintain a list of smart wallets that we create on behalf of users.
    // Later we may make it possible to detach your initial SignerSafe and assign a different smart contract wallet.
    mapping(address => SignerSafe) public signerSafes;

    event LogCreateSignerSafe(address indexed signer, address indexed signerSafe);

    event LogExecutePayload(address indexed signer, address indexed to, uint256 value, bytes data, string payload);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Add a domain, giving its owner the ability to register bots with usernames under it
    /// @param domain The domain you want to add
    /// @param domainOwner The account that can add bots under the domain
    function addDomain(string calldata domain, address domainOwner) external {
        require(msg.sender == owner, "Only the owner can add domains");
        domainOwners[keccak256(abi.encodePacked(domain))] = domainOwner;
    }

    /// @notice Add a bot under a domain you control, specifying the parser that will handle messages to it
    /// @param subdomain The subdomain, eg "bbs"
    /// @param domain The domain, eg "somedomain.example.com"
    /// @param parser A contract implementing IMessageParser that can handle messages for it
    function addBot(string calldata subdomain, string calldata domain, address parser) external {
        require(msg.sender == domainOwners[keccak256(abi.encodePacked(domain))], "Not your domain");
        require(parser != address(0), "Address not specified");
        bytes32 key = keccak256(abi.encodePacked(string.concat(string.concat(subdomain, "."), domain)));
        require(address(bots[key].parser) == address(0), "Subdomain already registered");
        bots[key] = Bot(domain, subdomain, parser);
    }

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

    /// @notice Translate a data node containing a message into a contract address, value and transaction bytecode
    /// @param content A data node containing a skeet
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    /// @return target The contract to call from the user's smart wallet
    /// @return value The value to send from the user's smart wallet
    /// @return botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    function _parsePayload(bytes calldata content, uint8 botNameLength)
        internal
        view
        returns (address, uint256 value, bytes memory)
    {
        uint256 cursor;
        uint256 nextLen;

        // Mapping byte
        cursor = 1;

        // Extract the message from the CBOR
        assert(bytes5(content[cursor:cursor + 5]) == CBOR_HEADER_TEXT_5);
        cursor = cursor + 5;
        (, nextLen, cursor) = CBORDecoder.parseCborHeader(content, cursor); // value
        require(bytes1(content[cursor:cursor + 1]) == bytes1(hex"40"), "Message should begin with @");
        bytes calldata message = content[cursor:cursor + nextLen];

        // Look up the bot name which should be in the first <256 bytes of the message followed by a space
        address bot = bots[keccak256(message[1:1 + botNameLength])].parser;
        require(address(bot) != address(0), "Bot not found");
        require(bytes1(message[1 + botNameLength:1 + botNameLength + 1]) == bytes1(hex"20"), "No space after bot name");

        return IMessageParser(bot).parseMessage(message[1 + botNameLength + 1:]);
    }

    /// @notice Predict the address that the specified signer will be assigned if they make a SignerSafe
    /// @param _signer The address
    function predictSafeAddress(address _signer) external view returns (address) {
        bytes32 salt = bytes32(uint256(uint160(_signer)));
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(type(SignerSafe).creationCode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Predict the address that the signer who created the specified signature will be assigned if they make a SignerSafe
    /// @param _v The signature v parameter (probably 28)
    /// @param _r The signature r parameter
    /// @param _s The signature s parameter
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

    /// @notice Predict the address that the signer who created the specified signature will have
    /// @dev This address is only used internally. People should send you stuff at your SignerSafe address, not this address
    /// @param sigHash The hash the signature signed
    /// @param _v The signature v parameter (probably 28)
    /// @param _r The signature r parameter
    /// @param _s The signature s parameter
    function predictSignerAddressFromSig(bytes32 sigHash, uint8 _v, bytes32 _r, bytes32 _s)
        public
        pure
        returns (address)
    {
        return ecrecover(sigHash, _v, _r, _s);
    }

    /// @notice Check that the supplied commit node includes the supplied root hash, or revert if it doesn't.
    /// @param proveMe The hash of the MST root node which is signed by the commit node supplied
    /// @param commitNode The CBOR-encoded commit node
    function assertCommitNodeContainsData(bytes32 proveMe, bytes calldata commitNode) public pure {
        uint256 cursor;
        uint256 extra;

        // mapping byte
        cursor = 1;

        assert(bytes5(commitNode[cursor:cursor + 4]) == CBOR_HEADER_DID_4);
        cursor = cursor + 4;
        (, extra, cursor) = CBORDecoder.parseCborHeader(commitNode, cursor);
        cursor = cursor + extra;

        assert(bytes4(commitNode[cursor:cursor + 4]) == CBOR_HEADER_REV_4);
        cursor = cursor + 4;
        (, extra, cursor) = CBORDecoder.parseCborHeader(commitNode, cursor);
        cursor = cursor + extra;

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

            // parseCborHeader either tells us the length of the data, or tells us the data itself if it could fit in the header.
            // It also advances the cursor to the end of the header.
            // If the data didn't fit in the header, we then read the data manually as a calldata slice and advance the cursor ourselves.
            uint256 extra;
            uint256 cursor;

            // mapping byte a2
            cursor = 1;

            assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_E_2);
            cursor = cursor + 2;
            (, numEntries, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor); // e array header

            // If the node is in an "e" entry, we only have to loop as far as the index of the entry we want
            // If the node is in the "l", we'll have to go through them all to find where "l" starts
            require(hint <= numEntries, "Hint is for an index beyond the end of the entries");
            if (hint > 0) {
                numEntries = hint;
            }

            for (uint256 i = 0; i < numEntries; i++) {
                // mapping byte a4
                cursor = cursor + 1;

                // For the first node, which contains information about the skeet, we also need the record key (k) in the relevant entry.
                // This uses a compression scheme where we have to construct it from the k and p of earlier entries.
                // For all later nodes we can ignore the value but we still have to check the field lengths to know how far to advance the cursor.

                if (n == 0) {
                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_K_2);
                    cursor = cursor + 2;

                    (, extra, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor);
                    string memory kval = string(nodes[n][cursor:cursor + extra]);
                    cursor = cursor + extra;

                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_P_2);
                    cursor = cursor + 2;
                    // For an int the cursor is already advanced
                    (, extra,) = CBORDecoder.parseCborHeader(nodes[n], cursor); // value
                    uint8 pval = uint8(extra);
                    // TODO: Check why the library didn't do this. Would it have done it when we called readInt?
                    cursor = cursor + 1;
                    if (pval >= 24) {
                        cursor = cursor + 1;
                    }

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

                    // Variable-length string
                    (, extra, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor);
                    cursor = cursor + extra;

                    assert(bytes2(nodes[n][cursor:cursor + 2]) == CBOR_HEADER_P_2);
                    cursor = cursor + 2;

                    // For an int the val is in the header so we shouldn't need to advance cursor beyond what parseCborHeader did
                    // TODO: Make sure this works if p > 24 and it needs the extra byte
                    (, extra, cursor) = CBORDecoder.parseCborHeader(nodes[n], cursor); // val
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

    /// @notice Perform some action on behalf of the sender of a skeet
    /// @param content A data node containing a skeet
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    /// @param nodes An array of CBOR-encoded tree nodes, ending in the root node for the MST
    /// @param nodeHints An array of indexes to help the verifier find the relevant data in the tree nodes
    /// @param commitNode The commit node at the top of the tree, CBOR-encoded with the signature removed
    /// @param _v The v parameter of the signature (probably 28)
    /// @param _r The r parameter of the signature
    /// @param _s The s parameter of the signature
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

    /// @notice Execute the specified content on behalf of the specified signer
    /// @param signer The user on whose behalf an action will be taken
    /// @param content A data node containing a skeet
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    function executePayload(address signer, bytes calldata content, uint8 botNameLength) internal {
        require(signer != address(0), "Signer should not be empty");

        // Every user action will be done in the context of their smart contract wallet.
        // If they don't already have one, create it for them now.
        // The address used is deterministic, so you can check what it will be and send stuff to it before we create it.
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        // Parsing will map the text of the message in the data node to a contract to interact with and some EVM code to execute against it.
        (address to, uint256 value, bytes memory payloadData) = _parsePayload(content, botNameLength);

        // The user's smart wallet should recognize this contract as their owner and execute what we send it.
        // Later we may allow it to detach itself from us and be controlled a different way, in which case this will fail.
        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, 0, payloadData, string(content));
    }
}
