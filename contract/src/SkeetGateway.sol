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

    function _parsePayload(string memory _payload) internal returns (address, uint256, bytes memory) {
        address to = address(bytes20(bytes(_payload)));
        // bytes memory data = bytes(_payload);
        bytes memory data = abi.encodeWithSignature("postMessage(string)", _payload);
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

    // Handles a skeet and 
    function handleSkeet(string memory _payload, uint256[] memory _offsets, bytes32[] memory _proofHashes, uint8 _v, bytes32 _r, bytes32 _s) external {

        // TODO: If the signature is p256 we need something like
        // https://github.com/daimo-eth/p256-verifier      
        // ...until such time as Ethereum adopts:
        // https://ethereum-magicians.org/t/eip-7212-precompiled-for-secp256r1-curve-support/14789/15
        // This takes different parameters to ecrecover, we have to pass in the pubkey.

        // TODO I guess this is always sha256 even when the signing is done with k256
        bytes32 sigHash = keccak256(abi.encodePacked(_payload));
        // require(sigHash == _proofHashes[0], "payload hash does not match the hash of its leaf node");

        address signer = ecrecover(sigHash, _v, _r, _s);
        require(signer != address(0), "Signer should not be empty");
        if (address(signerSafes[signer]) == address(0)) {
            bytes32 salt = bytes32(uint256(uint160(signer)));
            signerSafes[signer] = new SignerSafe{salt: salt}();
            require(address(signerSafes[signer]) != address(0), "Safe not created");
            emit LogCreateSignerSafe(signer, address(signerSafes[signer]));
        }

        (address to, uint256 value, bytes memory payloadData) = _parsePayload(_payload);
        signerSafes[signer].executeOwnerCall(to, value, payloadData);
        emit LogExecutePayload(signer, to, value, payloadData, _payload);
    }
    
}
