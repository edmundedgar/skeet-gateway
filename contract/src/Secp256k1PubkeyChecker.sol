// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// This is a function taken from:
// https://github.com/androlo/standard-contracts/blob/master/contracts/src/crypto/Secp256k1.sol

abstract contract Secp256k1PubkeyChecker {
    uint256 constant p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    function isPubkeyOnCurve(uint256 x, uint256 y) public pure returns (bool) {
        if (0 == x || x == p || 0 == y || y == p) {
            return false;
        }
        uint256 lhs = mulmod(y, y, p);
        uint256 rhs = addmod(mulmod(mulmod(x, x, p), x, p), 7, p);
        return lhs == rhs;
    }
}
