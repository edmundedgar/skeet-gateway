// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Secp256k1PubkeyCompression} from "../src/Secp256k1PubkeyCompression.sol";

contract Secp256k1PubkeyCompressionClient is Secp256k1PubkeyCompression {
    function callIsPubkeyOnCurve(bytes calldata pubkey) public returns (bool) {
        return isPubkeyOnCurve(pubkey);
    }
}

contract Secp256k1PubkeyCompressionTest is Test {
    // decompressed key:
    // x 8fe3769f5055088b448ca064bcecd7b6844239c355c98d4556d5c9c8c522de78
    // y 4fdc4cd480dc7b99d505243ec026409569a69842dbae649940cf7e8496efa31d

    function testCompressionByte() external {
        Secp256k1PubkeyCompressionClient client = new Secp256k1PubkeyCompressionClient();
        bytes32 y = 0x4fdc4cd480dc7b99d505243ec026409569a69842dbae649940cf7e8496efa31d;
        assertEq(client.compressionByte(y), bytes1(hex"03"), "even byte should be 03");

        // examples from https://medium.com/asecuritysite-when-bob-met-alice/02-03-or-04-so-what-are-compressed-and-uncompressed-public-keys-6abcb57efeb6

        // y
        bytes32 y2 = 0x88742f4dc97d9edb6fd946babc002fdfb06f26caf117b9405ed79275763fdb1c;
        assertEq(client.compressionByte(y2), bytes1(hex"02"), "even byte should be 02");

        bytes32 y3 = 0x4c220d01e1ca419cb1ba4b3393b615e99dd20aa6bf071078f70fd949008e7411;
        assertEq(client.compressionByte(y3), bytes1(hex"03"), "odd byte should be 03");
    }

    function testIsPubkeyOnCurve() public {
        Secp256k1PubkeyCompressionClient client = new Secp256k1PubkeyCompressionClient();

        bytes32 x = 0x8fe3769f5055088b448ca064bcecd7b6844239c355c98d4556d5c9c8c522de78;
        bytes32 y = 0x4fdc4cd480dc7b99d505243ec026409569a69842dbae649940cf7e8496efa31d;
        bytes memory pubkey = bytes.concat(x, y);
        assertTrue(client.callIsPubkeyOnCurve(pubkey), "real decompressed pubkey should be true");

        bytes32 xMonkey = x;
        for (uint256 i = 1; i < 1000; i++) {
            xMonkey = bytes32(uint256(xMonkey) - i);
            assertFalse(
                client.callIsPubkeyOnCurve(bytes.concat(xMonkey, y)), "monkeying around with x results in off-curve"
            );
        }

        bytes32 yMonkey = y;
        for (uint256 j = 1; j < 1000; j++) {
            yMonkey = bytes32(uint256(yMonkey) - j);
            assertFalse(
                client.callIsPubkeyOnCurve(bytes.concat(x, yMonkey)), "monkeying around with y results in off-curve"
            );
        }
    }
}
