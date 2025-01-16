// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// This is a minimal library to handle secp256k1 key compression based on:
// https://github.com/androlo/standard-contracts/blob/master/contracts/src/crypto/Secp256k1.sol

abstract contract Secp256k1PubkeyCompression {
    uint256 constant p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    function isPubkeyOnCurve(bytes calldata pubkey) public pure returns (bool) {
        uint256 x = uint256(bytes32(pubkey[0:32]));
        uint256 y = uint256(bytes32(pubkey[32:64]));
        if (0 == x || x == p || 0 == y || y == p) {
            return false;
        }
        uint256 lhs = mulmod(y, y, p);
        uint256 rhs = addmod(mulmod(mulmod(x, x, p), x, p), 7, p);
        return lhs == rhs;
    }

    function compressionByte(bytes32 y) public pure returns (bytes1) {
        // return 02 for even or 03 for odd
        return uint256(y) & 1 == 1 ? bytes1(hex"03") : bytes1(hex"02");
    }
}
