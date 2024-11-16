// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignerSafe} from "../src/SignerSafe.sol";
import {BBS} from "../src/BBS.sol";

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

    function verifyMerkleProof(bytes32[] memory proofHashes) public {
    }

    // Handles a skeet and 
    function handleSkeet(string memory _payload, uint256[] memory _offsets, bytes32[] memory _proofHashes, uint8 _v, bytes32 _r, bytes32 _s) external {

        // TODO: If the signature is p256 we need something like
        // https://github.com/daimo-eth/p256-verifier      
        // ...until such time as Ethereum adopts:
        // https://ethereum-magicians.org/t/eip-7212-precompiled-for-secp256r1-curve-support/14789/15
        // This takes different parameters to ecrecover, we have to pass in the pubkey.

        // TODO I guess this is always sha256 even when the signing is done with k256
        bytes32 sigHash = sha256(abi.encodePacked(_payload));
        require(sigHash == _proofHashes[0], "payload hash does not match the hash of its leaf node");

        verifyMerkleProof(_proofHashes);

        address signer = ecrecover(sigHash, _v, _r, _s);
        require(signer != address(0), "Signer should not be empty");
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        (address to, uint256 value, bytes memory payloadData) = _parsePayload(_payload, _offsets);
        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, value, payloadData, _payload);
    }
    
}
