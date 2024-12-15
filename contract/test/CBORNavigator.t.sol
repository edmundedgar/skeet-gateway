// SPDX-License-Identifier: UNLICeNSeD
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CBORNavigator} from "../src/CBORNavigator.sol";
import {console} from "forge-std/console.sol";

bytes constant CBOR_HEADER_TEXT_5 = bytes(hex"6474657874"); // text, "text"
bytes constant CBOR_HEADER_TYPE_6 = bytes(hex"652474797065"); // text, "$type"

contract CBORNavigatorClient {
    function indexOfMappingField(
        bytes calldata cbor,
        bytes memory fieldHeader,
        uint256 cursor
    ) external pure returns (uint256) {
        return CBORNavigator.indexOfMappingField(cbor, fieldHeader, cursor);
    }

    function cborFieldMetaData(bytes calldata cbor, uint256 byteIndex)
        external
        pure
        returns (uint256, uint256, uint64)
    {
        return CBORNavigator.cborFieldMetaData(cbor, byteIndex);
    }
}

contract CBORNavigatorTest is Test {
    bytes cborMap;
    CBORNavigatorClient client;

    function setUp() public {
        client = new CBORNavigatorClient();

        // A5                                     # map(5) #1
        //   6B                                   # text(11) #1
        //      736D616C6C4e756D626572            # "smallNumber" #11
        //   04                                   # unsigned(4) #1
        //   6B                                   # text(11) #1
        //      6C617267654e756D626572            # "largeNumber" #11
        //   1A 0098967F                          # unsigned(9999999) #5
        //   6B                                   # text(11) #1
        //      736D616C6C537472696e67            # "smallString" #11
        //   62                                   # text(2) #1
        //      6869                              # "hi" #2
        //   6C                                   # text(12) #1
        //      6D656469756D537472696e67          # "mediumString" #12
        //   78 40                                # text(64) #2
        //      4D6F6e6461792C206e6F7468696e6720547565736461792C204e6F7468696e672C205765646e657364617920616e64207468757273646179206e6F7468696e67 # "Monday, nothing Tuesday, Nothing, Wednesday and thursday nothing" #128
        //   6A                                   # text(10) #1
        //      6C6F6e67537472696e67              # "longString" #10
        //   79 010D                              # text(269) #3
        //      53696e67206C6F7665722073696e672e204465617468206973206120636F6D696e20696e2e2053696e67206C6F7665722073696e672e204465617468206973206120636F6D696e20696e2e20596F752063616e2774206F757477616C6B2074686520616e67656C206F662064656174682e2053696e67206375636B6F6F2073696e672e20596F752063616e2774206F757474616C6B2074686520616e67656C206F662064656174682e2053696e67206375636B6F6F2073696e672e204974277320616e206F6C6420636C696368C3A92074686174206974277320616e206F6C6420636C696368C3A92e2042757420796F7520626574746572206D616B6520796F7572206C6F766520746F646179 # "Sing lover sing. Death is a comin in. Sing lover sing. Death is a comin in. You can't outwalk the angel of death. Sing cuckoo sing. You can't outtalk the angel of death. Sing cuckoo sing. It's an old cliché that it's an old cliché. But you better make your love today" #269

        cborMap = bytes(
            hex"a56b736d616c6c4e756d626572046b6c617267654e756d6265721a0098967f6b736d616c6c537472696e676268696c6d656469756d537472696e6778404d6f6e6461792c206e6f7468696e6720547565736461792c204e6f7468696e672c205765646e657364617920616e64207468757273646179206e6f7468696e676a6c6f6e67537472696e6779010d53696e67206c6f7665722073696e672e204465617468206973206120636f6d696e20696e2e2053696e67206c6f7665722073696e672e204465617468206973206120636f6d696e20696e2e20596f752063616e2774206f757477616c6b2074686520616e67656c206f662064656174682e2053696e67206375636b6f6f2073696e672e20596f752063616e2774206f757474616c6b2074686520616e67656c206f662064656174682e2053696e67206375636b6f6f2073696e672e204974277320616e206f6c6420636c696368c3a92074686174206974277320616e206f6c6420636c696368c3a92e2042757420796f7520626574746572206d616b6520796f7572206c6f766520746f646179"
        );
    }
    /*
    atproto assumptions I can save a fair bit of gas if I can rely on:

    1) signode is did, version, data, rev,  prev encoded in that order
    2) tree nodes are e, l in that order, and e is k, p, t, v in that order (ie this one is sorted)
    3) skeets have "text" first, before various other stuff
    */

    function testCborMetaData() public {
        uint256 payloadStart;
        uint256 payloadEnd;
        uint64 extraData;
        uint256 cursor = 1;
        (payloadStart, payloadEnd, extraData) = client.cborFieldMetaData(cborMap, 1);
        assertEq(payloadEnd, 1 + 1 + 11);
        assertEq(0, extraData);

        cursor = 1 + 2 + 11 - 1;
        (payloadStart, payloadEnd, extraData) = client.cborFieldMetaData(cborMap, cursor);
        assertEq(4, extraData);

        cursor = 1 + 2 + 11 + 1 + 1 + 11 - 1;
        (payloadStart, payloadEnd, extraData) = client.cborFieldMetaData(cborMap, cursor);
        assertEq(9999999, extraData);
    }

    function testIndexOfMappingField() public {
        uint256 cursor = 1 + 1 + 11 + 1 + 1 + 11;
        bytes memory largeFieldText = bytes(hex"6b6c617267654e756d626572");
        uint256 index = client.indexOfMappingField(cborMap, largeFieldText, 1);
        assertEq(index, cursor);
    }

    function testArrayLengthParsing() public {
        uint256 payloadStart;
        uint256 payloadEnd;
        uint64 extraData;
        bytes memory cborSimpleArray = bytes(hex"83010203");
        (payloadStart, payloadEnd, extraData) = client.cborFieldMetaData(cborSimpleArray, 0);
        assertEq(3, extraData);
    }
}
