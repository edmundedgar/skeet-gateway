// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignerSafe} from "../src/SignerSafe.sol";
import {BBS} from "../src/BBS.sol";
import {CBORDecoder} from "./CBORDecoder.sol";
import {console} from "forge-std/console.sol";

contract SkeetGateway {

    mapping(address => SignerSafe) public signerSafes;

    event LogCreateSignerSafe(
        address indexed signer,
        address indexed signerSafe
    );

    event LogExecutePayload(
        address indexed signer,
        address indexed to,
        uint256 value,
        bytes data,
        string payload
    );

    //event LogString(string mystr);

    function _substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex-startIndex);
        for(uint i = startIndex; i < endIndex; i++) {
            result[i-startIndex] = strBytes[i];
        }
        //emit LogString(string(result));
        return string(result);
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
	uint8 byteValue = uint8(char);
	if (byteValue >= uint8(bytes1('0')) && byteValue <= uint8(bytes1('9'))) {
	    return byteValue - uint8(bytes1('0'));
	} else if (byteValue >= uint8(bytes1('a')) && byteValue <= uint8(bytes1('f'))) {
	    return 10 + byteValue - uint8(bytes1('a'));
	} else if (byteValue >= uint8(bytes1('A')) && byteValue <= uint8(bytes1('F'))) {
	    return 10 + byteValue - uint8(bytes1('A'));
	}
    }

    function _stringToAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }
        return address(uint160(bytes20(addrBytes)));
    }

    function _parsePayload(string memory _payload, uint256[] memory _offsets) internal returns (address, uint256, bytes memory) {
        string memory main_part = _substring(_payload, _offsets[0], _offsets[1]);
        address to = _stringToAddress(_substring(main_part, 0, 42));
        // bytes memory data = bytes(payload);
        string memory message = _substring(main_part, 43, bytes(main_part).length);
        bytes memory data = abi.encodeWithSignature("postMessage(string)", message);
        return (to, 0, data);
    }

    function predictSafeAddress(bytes32 sigHash, uint8 _v, bytes32 _r, bytes32 _s) external view returns (address) {
        address signer = predictSignerAddress(sigHash, _v, _r, _s);
        bytes32 salt = bytes32(uint256(uint160(signer)));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), salt, keccak256(type(SignerSafe).creationCode)
            )
        );
        return address (uint160(uint(hash)));
    }

    function predictSignerAddress(bytes32 sigHash, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        return ecrecover(sigHash, _v, _r, _s);
    }

    function merkleProvenSighash(bytes32[] calldata proofHashes) public returns (bytes32) {
    }

    function dataNodeRecordKeyForCID(bytes32 cid, bytes calldata dataNode, uint256 dataNodeEntryIdx) public returns (string memory) {

        // TODO: See if it's expensive gas to pass dataNode all the time
        // Maybe only pass the header, 2 bytes

        uint256 cursor;
        uint256 nextLen;
        uint256 numEntries;

        string memory rkey;

        // (, numEntries, cursor) = CBORDecoder.parseCborHeader(dataNode, 0); // the mapping for the node
        // require(numEntries == 2, "Should be 2 entries in the mapping");
        cursor = cursor + 1;

        //(, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // the e key
        cursor = cursor + 2; // (e text)
        // (, numEntries, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // the e array header
        cursor = cursor + 1; // (array)
        // require(dataNodeEntryIdx < numEntries, "e index provided is past the end of the array");

        for(uint256 i=0; i<=dataNodeEntryIdx; i++) {

            // The mapping entries show up in pairs, and each entry hash its own header
            // The parseCborHeader will advance the cursor to the beginning of the item (key or value)
            // We then read the bytes ourselves if we need them and advance the cursor to the start of the next header

            // (, , cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // mapping header
            cursor = cursor + 1; // a5 (map)

            // k
            // (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // key
            cursor = cursor + 2; // 61 65 (text k)

            (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // value
            string memory kval = string(dataNode[cursor:cursor+nextLen]);
            cursor = cursor + nextLen;

            // p
            (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // key
            bytes memory p = dataNode[cursor:cursor+nextLen];
            cursor = cursor + nextLen;

            // TODO: Check whether this may vary depending on the size of p
            (, nextLen, ) = CBORDecoder.parseCborHeader(dataNode, cursor); // value
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

            // t
            (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // key

            if (CBORDecoder.isNullNext(dataNode, cursor+1)) {
                cursor = cursor + 2;
            } else {
                //cursor = cursor + nextLen;
                // mystery d8 2a 58 then we get what we expect in 2500017
                cursor = cursor + 3;

                // (, nextLen, ) = CBORDecoder.parseCborHeader(dataNode, cursor); // value
                nextLen = 37;
                cursor = cursor + 2;

                cursor = cursor + nextLen;
            }

            // v 
            // (, , cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // key
            cursor = cursor + 1; // 61 76 (text v) TODO Check this

            // add mystery cid cursor
            cursor = cursor + 3;
            cursor = cursor + 2;
            nextLen = 37;
            // (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // value

            // If we're at the target dataNodeEntryIdx, read the value, check it and return the rkey
            // If we're not, skip it
            if (i == dataNodeEntryIdx) {
                require(keccak256(dataNode[cursor:cursor+nextLen]) == keccak256(bytes.concat(hex"0001711220", cid)), "Cid in data node did not match");
                return rkey;
            }
            cursor = cursor + nextLen;
        }

        /*
        No need to handle l
        // skip l
        (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // key
        cursor = cursor + nextLen;
        (, nextLen, cursor) = CBORDecoder.parseCborHeader(dataNode, cursor); // value
        cursor = cursor + nextLen;
        */

        revert("Entry not found in data node");

    }

    // Handles a skeet and 
    function handleSkeet(uint8 _v, bytes32 _r, bytes32 _s, bytes calldata rootCbor, bytes calldata dataCbor, uint256 dataNodeEntryIdx, bytes[] calldata treeCbors) external {





        // TODO: If the signature is p256 we need something like
        // https://github.com/daimo-eth/p256-verifier      
        // ...until such time as Ethereum adopts:
        // https://ethereum-magicians.org/t/eip-7212-precompiled-for-secp256r1-curve-support/14789/15
        // This takes different parameters to ecrecover, we have to pass in the pubkey.

        // TODO I guess this is always sha256 even when the signing is done with k256
        bytes32 rootCborHash = sha256(abi.encodePacked(rootCbor));

        address signer = ecrecover(rootCborHash, _v, _r, _s);
        require(signer != address(0), "Signer should not be empty");
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        /*
        string payload = 'replaceme';


        (address to, uint256 value, bytes memory payloadData) = _parsePayload(payload, _offsets);
        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, value, payloadData, _payload);
        */
    }
    
}
