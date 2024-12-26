// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AtprotoMSTProver} from "../src/AtprotoMSTProver.sol";
import {SignerSafe} from "../src/SignerSafe.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {IMessageParserFull} from "../src/parsers/IMessageParserFull.sol";
import {console} from "forge-std/console.sol";

contract SkeetGateway is AtprotoMSTProver {
    // Skeets are addressed to a username, eg bbs.bots.example.com
    // The username will be mapped to a contract which translate text into a contract address and transaction code.
    struct Bot {
        string domain;
        string subdomain;
        address parser;
        bool needFullMessage;
    }

    mapping(bytes32 => Bot) public bots;

    // The owner has only one single privileged role, the ability to add a domain and assign it to an administrator.
    // If you own a domain, you have the ability to register bots under that domain.
    address public owner;
    mapping(bytes32 => address) public domainOwners;

    // We maintain a list of smart wallets that we create on behalf of users.
    // Later we may make it possible to detach your initial SignerSafe and assign a different smart contract wallet.
    mapping(address => SignerSafe) public signerSafes;

    mapping(address => mapping(bytes32 => bool)) handledMessages;

    event LogCreateSignerSafe(address indexed signer, address indexed signerSafe);

    event LogExecutePayload(address indexed signer, address indexed to, uint256 value, bytes data);

    event LogAddDomain(address indexed owner, string domain);

    event LogAddBot(address indexed parser, string domain, string subdomain, bool needFullMessage);

    event LogChangeOwner(address indexed owner);

    constructor() {
        owner = msg.sender;
        emit LogChangeOwner(owner);
    }

    /// @notice Change the contract owner (who has the ability to add domains)
    /// @param _owner The new owner of the contract
    function changeOwner(address _owner) external {
        require(msg.sender == owner, "Only the existing owner can change the owner");
        owner = _owner;
        emit LogChangeOwner(_owner);
    }

    /// @notice Add a domain, giving its owner the ability to register bots with usernames under it
    /// @param domain The domain you want to add
    /// @param domainOwner The account that can add bots under the domain
    function addDomain(string calldata domain, address domainOwner) external {
        require(msg.sender == owner, "Only the owner can add domains");
        domainOwners[keccak256(abi.encodePacked(domain))] = domainOwner;
        emit LogAddDomain(domainOwner, domain);
    }

    /// @notice Add a bot under a domain you control, specifying the parser that will handle messages to it
    /// @param subdomain The subdomain, eg "bbs"
    /// @param domain The domain, eg "somedomain.example.com"
    /// @param parser A contract implementing IMessageParser that can handle messages for it
    function addBot(string calldata subdomain, string calldata domain, address parser, bool needFullMessage) external {
        require(msg.sender == domainOwners[keccak256(abi.encodePacked(domain))], "Not your domain");
        require(parser != address(0), "Address not specified");
        bytes32 key = keccak256(abi.encodePacked(string.concat(string.concat(subdomain, "."), domain)));
        require(address(bots[key].parser) == address(0), "Subdomain already registered");
        bots[key] = Bot(domain, subdomain, parser, needFullMessage);
        emit LogAddBot(parser, domain, subdomain, needFullMessage);
    }

    /// @notice Translate a data node containing a message into a contract address, value and transaction bytecode
    /// @param content A data node containing a skeet
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    /// @return target The contract to call from the user's smart wallet
    /// @return value The value to send from the user's smart wallet
    /// @return botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    function _parsePayload(bytes[] calldata content, uint8 botNameLength)
        internal
        returns (address, uint256 value, bytes memory)
    {
        uint256 textStart;
        uint256 textEnd;
        (textStart, textEnd) = indexOfMessageText(content[0]);
        require(bytes1(content[0][textStart:textStart + 1]) == bytes1(hex"40"), "Message should begin with @");

        // Look up the bot name which should be in the first <256 bytes of the message followed by a space
        Bot memory bot = bots[keccak256(content[0][textStart + 1:textStart + 1 + botNameLength])];
        address parser = bot.parser;

        require(address(parser) != address(0), "Bot not found");
        require(bytes1(content[0][textStart + 1 + botNameLength:textStart + 1 + botNameLength + 1]) == bytes1(hex"20"), "No space after bot name");

        if (bot.needFullMessage) {
            return IMessageParserFull(parser).parseFullMessage(content, textStart + 1 + botNameLength + 1, textEnd);
        } else {
            return IMessageParser(parser).parseMessage(content[0][textStart + 1 + botNameLength + 1:textEnd]);
        }
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

    /// @notice Perform some action on behalf of the sender of a skeet
    /// @param content A content node containing a skeet, with an optional extra one containing reply context
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    /// @param nodes An array of CBOR-encoded tree nodes, ending in the root node for the MST
    /// @param nodeHints An array of indexes to help the verifier find the relevant data in the tree nodes
    /// @param commitNode The commit node at the top of the tree, CBOR-encoded with the signature removed
    /// @param _v The v parameter of the signature (probably 28)
    /// @param _r The r parameter of the signature
    /// @param _s The s parameter of the signature
    function handleSkeet(
        bytes[] calldata content,
        uint8 botNameLength,
        bytes[] calldata nodes,
        uint256[] calldata nodeHints,
        bytes calldata commitNode,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        {
            bytes32 target = sha256(abi.encodePacked(content[0]));
            (bytes32 rootHash, string memory rkey) = merkleProvenRootHash(target, nodes, nodeHints);
            // TODO: Add replay protection
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
    function executePayload(address signer, bytes[] calldata content, uint8 botNameLength) internal {
        require(signer != address(0), "Signer should not be empty");

        // TODO We already hashed this in handleSkeet but couldn't reuse the hash for stack-too-deep reasons
        // See if we reorganize things to get around the need to do the hashing twice
        bytes32 contentHash = keccak256(content[0]);
        require(!handledMessages[signer][contentHash], "Already handled");
        handledMessages[signer][contentHash] = true;

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
        emit LogExecutePayload(signer, to, value, payloadData);
    }
}
