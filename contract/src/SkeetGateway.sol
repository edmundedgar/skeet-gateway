// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AtprotoMSTProver} from "../src/AtprotoMSTProver.sol";
import {IMessageParser} from "../src/parsers/IMessageParser.sol";
import {console} from "forge-std/console.sol";

import {SafeProxy} from "../lib/safe-contracts/contracts/proxies/SafeProxy.sol";
import {Safe} from "../lib/safe-contracts/contracts/Safe.sol";
import {Enum} from "../lib/safe-contracts/contracts/libraries/Enum.sol";

import {ShadowDIDPLCDirectory} from "./ShadowDIDPLCDirectory.sol";

contract SkeetGateway is AtprotoMSTProver {
    // Skeets are addressed to a username, eg bbs.bots.example.com
    // The username will be mapped to a contract which translate text into a contract address and transaction code.
    struct Bot {
        string domain;
        string subdomain;
        address parser;
    }

    address public gnosisSafeSingleton;
    ShadowDIDPLCDirectory public shadowDIDPLCDirectory;
    uint256 public minUpdateMaturitySecs;
    address[] public didRepoTrustedObservers;

    mapping(bytes32 => Bot) public bots;

    // The owner has only one single privileged role, the ability to add a domain and assign it to an administrator.
    // If you own a domain, you have the ability to register bots under that domain.
    address public owner;
    mapping(bytes32 => address) public domainOwners;

    // We maintain a list of smart wallets that we create on behalf of users.
    // Later we may make it possible to detach your initial Safe and assign a different smart contract wallet.
    // user -> id -> safe
    mapping(bytes32 => mapping(uint256 => Safe)) public accountSafes;

    mapping(bytes32 => mapping(bytes32 => bool)) handledMessages;

    // How many safes have been created for each user
    // Each will use the index as part of its salt
    mapping(bytes32 => uint256) accountSafeCount;

    // The address of the safe you chose to be used for your next command
    // (The first safe will be created automatically, otherwise you must create them before selecting them)
    mapping(bytes32 => uint256) selectedSafeId;

    // If somebody transfers a safe to a signer, this is equivalent to somebody mailing you a free Ledger
    // ie you can control it, but it may have had malicious accounts/modules added or approvals granted on other contracts
    // use this to flag safes that have been assigned to you but you haven't confirmed people can use to send you stuff
    mapping(bytes32 => mapping(address => bool)) accountUnverifiedSafes;

    event LogCreateSafe(bytes32 indexed account, address indexed accountSafe, uint256 indexed safeId);

    event LogTransferSafe(
        bytes32 indexed oldAccount, uint256 oldSafeId, bytes32 indexed newAccount, uint256 indexed newSafeId
    );

    event LogExecutePayload(
        bytes32 indexed contentHash,
        bytes32 indexed account,
        address indexed to,
        uint256 value,
        bytes data,
        bool isApproval
    );

    event LogAddDomain(address indexed owner, string domain);

    event LogAddBot(address indexed parser, string domain, string subdomain, string metadata);

    event LogChangeOwner(address indexed owner);

    event LogHandleAccount(bytes32 indexed account, bytes32 indexed did, address indexed signer);

    address[] initialSafeOwners;

    constructor(
        address _gnosisSafeSingleton,
        address _shadowDIDPLCDirectory,
        uint256 _minUpdateMaturitySecs,
        address[] memory _didRepoTrustedObservers
    ) {
        owner = msg.sender;
        gnosisSafeSingleton = _gnosisSafeSingleton;
        shadowDIDPLCDirectory = ShadowDIDPLCDirectory(_shadowDIDPLCDirectory);
        minUpdateMaturitySecs = _minUpdateMaturitySecs;
        didRepoTrustedObservers = _didRepoTrustedObservers;

        initialSafeOwners.push(address(this));
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
    /// @param metadata Optional json-encoded settings to tell the caller what content to send, eg if the bot needs reply data
    function addBot(string calldata subdomain, string calldata domain, address parser, string calldata metadata)
        external
    {
        require(msg.sender == domainOwners[keccak256(abi.encodePacked(domain))], "Not your domain");
        require(parser != address(0), "Address not specified");
        bytes32 key = keccak256(abi.encodePacked(string.concat(string.concat(subdomain, "."), domain)));
        require(address(bots[key].parser) == address(0), "Subdomain already registered");
        bots[key] = Bot(domain, subdomain, parser);
        emit LogAddBot(parser, domain, subdomain, metadata);
    }

    /// @notice Translate a data node containing a message into a contract address, value and transaction bytecode
    /// @param content A data node containing a skeet
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    /// @return target The contract to call from the user's smart wallet
    /// @return value The value to send from the user's smart wallet
    /// @return data The data to execute from the user's smart wallet
    function _parsePayload(bytes[] calldata content, uint8 botNameLength, address accountSafe)
        internal
        returns (address, uint256 value, bytes memory)
    {
        uint256 textStart;
        uint256 textEnd;
        (textStart, textEnd) = indexOfMessageText(content[0]);
        bytes calldata message = content[0][textStart:textEnd];
        require(bytes1(message[0:1]) == bytes1(hex"40"), "Message should begin with @");

        // Look up the bot name which should be in the first <256 bytes of the message followed by a space
        address bot = bots[keccak256(message[1:1 + botNameLength])].parser;
        require(address(bot) != address(0), "Bot not found");
        require(bytes1(message[1 + botNameLength:1 + botNameLength + 1]) == bytes1(hex"20"), "No space after bot name");

        return IMessageParser(bot).parseMessage(content, textStart + 1 + botNameLength + 1, textEnd, accountSafe);
    }

    /// @notice Return the account for the specified did and signer
    /// @param _did The did the safe will belong to
    /// @param _signer The signer the safe will belong to
    function calculateAccount(bytes32 _did, address _signer) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_did, _signer));
    }

    /// @notice Return the address of the user's currently selected safe
    /// @param _did The did the safe will belong to
    /// @param _signer The signer the safe will belong to
    function selectedSafeAddress(bytes32 _did, address _signer) external view returns (address) {
        bytes32 account = keccak256(abi.encodePacked(_did, _signer));
        uint256 selectedId = selectedSafeId[account];
        address existingSafe = address(accountSafes[account][selectedId]);
        if (existingSafe == address(0)) {
            return predictSafeAddress(account, selectedId);
        } else {
            return existingSafe;
        }
    }

    /// @notice Predict the address that the specified account will be assigned if they make a Safe
    /// @param _account The account the safe will belong to
    function predictSafeAddress(bytes32 _account, uint256 _safeId) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_account, _safeId));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(abi.encodePacked(type(SafeProxy).creationCode, uint256(uint160(gnosisSafeSingleton))))
            )
        );
        return address(uint160(uint256(hash)));
    }

    /// @notice Predict the address that the signer who created the specified signature will be assigned if they make a Safe
    /// @param sig The signature in gnosis safe style (65 bytes, r+s+v)
    function predictSafeAddressFromDidAndSig(bytes32 did, bytes32 sigHash, bytes calldata sig, uint256 safeId)
        external
        view
        returns (address)
    {
        address signer = predictSignerAddressFromSig(sigHash, sig);
        bytes32 account = keccak256(abi.encodePacked(did, signer));
        return predictSafeAddress(account, safeId);
    }

    /// @notice Predict the address that the signer who created the specified signature will have
    /// @dev This address is only used internally. People should send you stuff at your Safe address, not this address
    /// @param sigHash The hash the signature signed
    /// @param sig The signature in gnosis safe style (r+s+v)
    function predictSignerAddressFromSig(bytes32 sigHash, bytes calldata sig) public pure returns (address) {
        return ecrecover(sigHash, uint8(bytes1(sig[64:65])), bytes32(sig[0:32]), bytes32(sig[32:64]));
    }

    /// @notice Verify the commit node signs rootHash, and return the account it is signed with
    /// @param rootHash The hash of the MST root node which is signed by the commit node supplied
    /// @param commitNode The CBOR-encoded commit node
    /// @return did a bytes32 representing the account (DID + signer)
    function _verifyAndRecoverAccount(bytes32 rootHash, bytes calldata commitNode, bytes calldata sig)
        internal
        returns (bytes32)
    {
        bytes32 commitNodeHash = sha256(abi.encodePacked(commitNode));
        address signer = ecrecover(commitNodeHash, uint8(bytes1(sig[64:65])), bytes32(sig[0:32]), bytes32(sig[32:64]));

        // This is the DID the signer is claiming to be speaking for in their signed commit node
        // They may or may not be the legitimate signer per the PLC directory / signed DID updates
        bytes32 did = processCommitNode(rootHash, commitNode);
        bytes32 account = keccak256(abi.encodePacked(did, signer));
        emit LogHandleAccount(account, did, signer);
        return account;
    }

    /// @notice Perform some action on behalf of the sender of a skeet
    /// @param content A content node containing a skeet, with an optional extra one containing reply context
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    /// @param nodes An array of CBOR-encoded tree nodes, ending in the root node for the MST
    /// @param nodeHints An array of indexes to help the verifier find the relevant data in the tree nodes
    /// @param commitNode The commit node at the top of the tree, CBOR-encoded with the signature removed
    /// @param sig The signature in Gnosis Safe style (r+s+v)
    function handleSkeet(
        bytes[] calldata content,
        uint8 botNameLength,
        bytes[] calldata nodes,
        uint256[] calldata nodeHints,
        bytes calldata commitNode,
        bytes calldata sig
    ) external {
        bytes32 contentHash = sha256(abi.encodePacked(content[0]));
        bytes32 rootHash = merkleProvenRootHash(contentHash, nodes, nodeHints);
        bytes32 account = _verifyAndRecoverAccount(rootHash, commitNode, sig);
        _executePayload(account, content, botNameLength);
    }

    /// @notice Return the users's safe at the given index, creating it if necessary
    /// @param account The user on whose behalf an action will be taken
    /// @param safeId The numerical ID of the safe (each user starts at 0)
    /// @return A Safe instance
    function _ensureSafeCreated(bytes32 account, uint256 safeId) internal returns (Safe) {
        Safe accountSafe = accountSafes[account][safeId];
        if (address(accountSafe) == address(0)) {
            bytes32 salt = keccak256(abi.encodePacked(account, safeId));
            accountSafe = Safe(payable(address(new SafeProxy{salt: salt}(gnosisSafeSingleton))));
            require(address(accountSafe) != address(0), "Safe not created");
            accountSafe.setup(
                initialSafeOwners, 1, address(0), bytes(""), address(0), address(0), 0, payable(address(0))
            );
            accountSafes[account][safeId] = accountSafe;
            accountSafeCount[account]++;
            emit LogCreateSafe(account, address(accountSafe), safeId);
        }
        return accountSafe;
    }

    function transferSafes(bytes32 _did, bytes32 _oldUpdateHash, bytes32 _newUpdateHash, uint256[] calldata safeIds)
        external
    {
        address oldAddress = shadowDIDPLCDirectory.verificationAddressAt(_did, _oldUpdateHash);
        require(oldAddress != address(0), "Old address not found");
        bytes32 oldAccount = keccak256(abi.encodePacked(_did, oldAddress));
        require(
            shadowDIDPLCDirectory.isUpdateConfirmedValid(
                _did, _newUpdateHash, minUpdateMaturitySecs, didRepoTrustedObservers
            ),
            "New update invalid"
        );
        address newAddress = shadowDIDPLCDirectory.verificationAddressAt(_did, _newUpdateHash);
        bytes32 newAccount = keccak256(abi.encodePacked(_did, newAddress));
        for (uint256 i = 0; i < safeIds.length; i++) {
            uint256 oldSafeId = safeIds[i];
            require(address(accountSafes[oldAccount][oldSafeId]) != address(0), "No safe to transfer");
            uint256 newSafeId = accountSafeCount[newAccount];
            accountSafes[newAccount][newSafeId] = accountSafes[oldAccount][oldSafeId];
            accountSafeCount[newAccount]++;
            delete(accountSafes[oldAccount][oldSafeId]);
            emit LogTransferSafe(oldAccount, oldSafeId, newAccount, newSafeId);
        }
    }

    /// @notice Execute the specified content on behalf of the specified signer
    /// @param account The user on whose behalf an action will be taken
    /// @param content A data node containing a skeet
    /// @param botNameLength The length in bytes of the name of the bot, mentioned at the start of the message
    function _executePayload(bytes32 account, bytes[] calldata content, uint8 botNameLength) internal {
        require(account != bytes32(0), "Signer should not be empty");

        // TODO We already hashed this in handleSkeet but couldn't reuse the hash for stack-too-deep reasons
        // See if we reorganize things to get around the need to do the hashing twice
        bytes32 contentHash = keccak256(content[0]);
        require(!handledMessages[account][contentHash], "Already handled");
        handledMessages[account][contentHash] = true;

        // Every user action will be done in the context of their smart contract wallet.
        // If they don't already have one, create it for them now.
        // The address used is deterministic, so you can check what it will be and send stuff to it before we create it.
        Safe accountSafe = _ensureSafeCreated(account, selectedSafeId[account]);

        // Parsing will map the text of the message in the data node to a contract to interact with and some EVM code to execute against it.
        (address to, uint256 value, bytes memory payloadData) =
            _parsePayload(content, botNameLength, address(accountSafe));

        if (accountSafe.getThreshold() > 1) {
            bytes32 txHash = accountSafe.getTransactionHash(
                to,
                value,
                payloadData,
                Enum.Operation.Call,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                accountSafe.nonce()
            );
            accountSafe.approveHash(txHash);
            emit LogExecutePayload(contentHash, account, to, value, payloadData, true);
        } else {
            // The user's smart wallet should recognize this contract as their owner and execute what we send it.
            // Later we may allow it to detach itself from us and be controlled a different way, in which case this will fail.
            require(
                accountSafe.execTransaction(
                    to,
                    value,
                    payloadData,
                    Enum.Operation.Call,
                    0,
                    0,
                    0,
                    address(0),
                    payable(address(0)),
                    abi.encodePacked(bytes32(uint256(uint160(address(this)))), bytes32(0), uint8(1)) // special fake signature for a contract call
                ),
                "Execution failed"
            );
            emit LogExecutePayload(contentHash, account, to, value, payloadData, false);
        }
    }

    function accountSafeForId(bytes32 account, uint256 safeId) external view returns (Safe) {
        return accountSafes[account][safeId];
    }
}
