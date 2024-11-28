// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignerSafe} from "../src/SignerSafe.sol";
import {BBS} from "../src/BBS.sol";
import "../lib/solidity-bsky-cbor/src/TreeCbor.sol";
import "../lib/solidity-bsky-cbor/src/CommitCbor.sol";
import "../lib/solidity-bsky-cbor/src/CidCbor.sol";
import "../lib/solidity-bsky-cbor/src/RecordCbor.sol";

contract SkeetGateway {
    mapping(address => SignerSafe) public signerSafes;

    event LogCreateSignerSafe(address indexed signer, address indexed signerSafe);

    event LogExecutePayload(address indexed signer, address indexed to, uint256 value);

    //event LogString(string mystr);

    function checkSig_secp256k1(address signer, bytes memory message, bytes32 r, bytes32 s)
        internal
        pure
        returns (bool)
    {
        return signer == ecrecover(sha256(message), 1 + 27, r, s);
    }

    bytes5 private constant text_send_space = bytes5("send ");
    bytes4 private constant space_to_space = bytes4(" to ");
    bytes1 private constant space = bytes1(" ");

    function numericStringToUint(bytes memory s) internal pure returns (uint256 result) {
        uint256 i;
        result = 0;
        for (i = 0; i < s.length; i++) {
            uint8 c = uint8(s[i]);
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
    }

    function parseRecordText(string memory text)
        internal
        pure
        returns (address to, uint256 amount, bytes memory payloadData)
    {
        require(bytes5(bytes(text)) == text_send_space, "Record text does not start with 'send '");

        bytes memory textBytes = bytes(text);
        uint8 secondSpaceIndex;
        for (uint8 i = 5; i < textBytes.length; i++) {
            if (textBytes[i] == space) {
                secondSpaceIndex = i;
                break;
            }
        }

        bytes memory numericStringBytes = new bytes(secondSpaceIndex - 5);
        for (uint8 i = 5; i < secondSpaceIndex; i++) {
            numericStringBytes[i - 5] = textBytes[i];
        }

        amount = numericStringToUint(numericStringBytes);
        return (to, amount, payloadData);
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
        require(signer == recover, "Invalid signature");

        require(signer != address(0), "Signer should not be empty");

        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        TreeCbor.Tree memory tree = TreeCbor.readTree(treeNodes);

        (CommitCbor.Commit memory rootCommit,) = CommitCbor.readCommit(commit, 0);
        Cid rootCid = rootCommit.data;

        string memory key = string.concat(collection, "/", rkey);

        require(TreeCbor.verifyInclusion(tree, rootCid, target, key), "Not included");

        (RecordCbor.Record memory record,) = RecordCbor.readRecord(target, 0);

        (address to, uint256 value, bytes memory payloadData) = parseRecordText(record.text);

        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, value);
    }
}
