// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {SignerSafe} from "../src/SignerSafe.sol";
import {BBS} from "../src/BBS.sol";
import "../lib/solidity-bsky-cbor/src/TreeCbor.sol";
import "../lib/solidity-bsky-cbor/src/CommitCbor.sol";
import "../lib/solidity-bsky-cbor/src/CidCbor.sol";

contract SkeetGateway {
    mapping(address => SignerSafe) public signerSafes;

    event LogCreateSignerSafe(address indexed signer, address indexed signerSafe);

    event LogExecutePayload(address indexed signer, address indexed to, uint256 value, bytes data, string payload);

    //event LogString(string mystr);

    function checkSig_secp256k1(address signer, bytes memory message, bytes32 r, bytes32 s)
        internal
        pure
        returns (bool)
    {
        return signer == ecrecover(sha256(message), 1 + 27, r, s);
    }

    // Handles a skeet and
    function handleSkeet(
        address signer,
        bytes32 r,
        bytes32 s,
        bytes memory commit,
        bytes[] memory treeNodes,
        bytes memory target,
        string memory collection,
        string memory rkey
    ) external {
        // TODO: If the signature is p256 we need something like
        // https://github.com/daimo-eth/p256-verifier
        // ...until such time as Ethereum adopts:
        // https://ethereum-magicians.org/t/eip-7212-precompiled-for-secp256r1-curve-support/14789/15
        // This takes different parameters to ecrecover, we have to pass in the pubkey.

        address recover = ecrecover(sha256(commit), 1 + 27, r, s);
        require(signer == recover);

        require(signer != address(0), "Signer should not be empty");

        /*
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }
        */

        TreeCbor.Tree memory tree = TreeCbor.readTree(treeNodes);
        console.log(tree.nodes.length);

        (CommitCbor.Commit memory rootCommit,) = CommitCbor.readCommit(commit, 0);
        CidCbor.CidBytes32 rootCid = CidCbor.readCidBytes32(commit, rootCommit.data);

        string memory key = string.concat(collection, "/", rkey);

        TreeCbor.verifyInclusion(tree, treeNodes, rootCid, target, key);
    }
}
