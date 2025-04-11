// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DagCborNavigator} from "../DagCborNavigator.sol";
import {console} from "forge-std/console.sol";

import {Base32} from "@0x00000002/ipfs-cid-solidity/contracts/Base32.sol";

bytes4 constant MULTIHASH_CID_DAGCBOR_SHA2_256 = hex"01711220";

bytes6 constant CBOR_HEADER_REPLY = hex"657265706C79"; // text(5) "reply"
// bytes7 constant CBOR_HEADER_PARENT = hex"66706172656E74"; // text(6) "parent"
bytes5 constant CBOR_HEADER_ROOT = hex"64726F6F74"; //  # text(4) "root"
bytes4 constant CBOR_HEADER_CID = hex"63636964"; // # # text(3) "cid"

contract ReplyVerifier {
    function _verifyReply(bytes[] calldata content) internal pure {
        uint256 cursor = 1;
        cursor = DagCborNavigator.indexOfMappingField(content[0], bytes.concat(CBOR_HEADER_REPLY), cursor);
        cursor = DagCborNavigator.indexOfMappingField(content[0], bytes.concat(CBOR_HEADER_ROOT), cursor + 1);
        cursor = DagCborNavigator.indexOfMappingField(content[0], bytes.concat(CBOR_HEADER_CID), cursor + 1);

        uint256 cidLength;
        (, cidLength, cursor) = DagCborNavigator.parseCborHeader(content[0], cursor);

        bytes memory expectedCid = Base32.encode(bytes.concat(MULTIHASH_CID_DAGCBOR_SHA2_256, sha256(content[1])));
        require(
            keccak256(expectedCid) == keccak256(content[0][cursor:cursor + cidLength]), "Reply provided did not match"
        );
    }
}
