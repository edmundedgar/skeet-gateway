//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@ensdomains/buffer/contracts/Buffer.sol";

import "./CBOREncoding.sol";
import "./CBORDecoding.sol";
import "./ByteParser.sol";

/**
 * @dev Documentation for contract.
 *
 */
contract CBORTesting {

    using Buffer for Buffer.buffer;

    bool private _state = false;

    /**
     * CBOR Decoding utilities
     */
    function testDecodeCBORMapping(bytes memory encoding) public view returns (bytes[2][] memory decodedData) {
        return CBORDecoding.decodeMapping(encoding);
    }

    function testDecodeCBORMappingGetValue(bytes memory encoding, bytes memory key) public view returns (bytes memory value) {
        return CBORDecoding.decodeMappingGetValue(encoding, key);
    }

    function testDecodeCBORArrayGetIndex(bytes memory encoding, bytes memory key) public view returns (uint64 index) {
        return CBORDecoding.decodeArrayGetIndex(encoding, key);
    }

    function testDecodeCBORArrayGetItem(bytes memory encoding, uint64 index) public view returns (bytes memory value) {
        return CBORDecoding.decodeArrayGetItem(encoding, index);
    }

    function testDecodeCBORArray(bytes memory encoding) public view returns (bytes[] memory decodedData) {
        return CBORDecoding.decodeArray(encoding);
    }

    function testDecodeCBORPrimitive(bytes memory encoding) public view returns (bytes memory decodedData) {
        return CBORDecoding.decodePrimitive(encoding);
    }

    /**
     * ByteParser utilities
     */

    function testBytesToNegativeInt128(bytes memory encoding) public view returns (int128) {
        return ByteParser.bytesToNegativeInt128(encoding);
    }

    function testBytesToUint64(bytes memory encoding) public view returns (uint64) {
        return ByteParser.bytesToUint64(encoding);
    }

    function testBytesToString(bytes memory encoding) public view returns (string memory) {
        return ByteParser.bytesToString(encoding);
    }

    function testBytesToBigNumber(bytes memory encoding) public view returns (uint256 value) {
        return ByteParser.bytesToBigNumber(encoding);
    }

    function testBytesToBool(bytes memory encoding) public view returns (bool state) {
        return ByteParser.bytesToBool(encoding);
    }

    /**
     * Benchmark how expensive decoding is (with state changes)
     * Call some state to measure how expensive our computations are
     */
    function baselineStateChange() public {
        _state = !_state;
    }

    function statefulTestDecodeCBORMapping(bytes memory encoding) public {
        _state = !_state;
        CBORTesting.testDecodeCBORMapping(encoding);
    }

    function statefulTestDecodeCBORMappingGetValue(bytes memory encoding, bytes memory key) public {
        _state = !_state;
        CBORTesting.testDecodeCBORMappingGetValue(encoding, key);
    }

    function statefulTestDecodeCBORArrayGetIndex(bytes memory encoding, bytes memory key) public {
        _state = !_state;
        CBORTesting.testDecodeCBORArrayGetIndex(encoding, key);
    }

    function statefulTestDecodeCBORArrayGetItem(bytes memory encoding, uint64 index) public {
        _state = !_state;
        CBORTesting.testDecodeCBORArrayGetItem(encoding, index);
    }

    function statefulTestDecodeCBORArray(bytes memory encoding) public {
        _state = !_state;
        CBORTesting.testDecodeCBORArray(encoding);
    }

    function statefulTestDecodeCBORPrimitive(bytes memory encoding) public {
        _state = !_state;
        CBORTesting.testDecodeCBORPrimitive(encoding);
    }

}
