// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CBORDecoding} from "../staticlib/solidity-cbor/CBORDecoding.sol";
import {console} from "forge-std/console.sol";

contract CBORDecodingTest is Test {

    function setUp() public {
    }

    function testDecode() public {
        /*
        rootRecordSansSig: {
            did: 'did:plc:mtq3e4mgt7wyjhhaniezej67',
            rev: '3laykltosp22q',
            data: CID(bafyreidg3jtflp4nu6nwtkdsthhrod7nqsl7umczg6o4jkf74hrizk25sm),
            prev: null,
            version: 3
        }
        Once it has signed it will add the signature to its rootRecord.
        We only care about the CID.
        */

        bytes memory cborSansSig = hex"a56364696478206469643a706c633a6d74713365346d67743777796a6868616e69657a656a3637637265766d336c61796b6c746f73703232716464617461d82a5825000171122066da6655bf8da79b69a87299cf170fed8497fa3059379dc4a8bfe1e28cab5d936470726576f66776657273696f6e03";
        //bytes[2][] memory result = CBORDecoding.decodeMapping(cborSansSig);
        //bytes memory result = CBORDecoding.decodePrimitive(cborSansSig);
        //return;
  
        bytes memory did = CBORDecoding.decodeMappingGetValue(cborSansSig, bytes("did"));
        assertEq(string(abi.encodePacked(did)), "did:plc:mtq3e4mgt7wyjhhaniezej67");

        bytes memory rev = CBORDecoding.decodeMappingGetValue(cborSansSig, bytes("rev"));
        assertEq(string(abi.encodePacked(rev)), "3laykltosp22q");

        bytes memory data = CBORDecoding.decodeMappingGetValue(cborSansSig, bytes("data"));
        assertEq(data.length, 32);
        /*
        assertEq(data.length, 32);
        bytes32 expected_data = 0x66da6655bf8da79b69a87299cf170fed8497fa3059379dc4a8bfe1e28cab5d93;
        bytes32 dataB32 = bytes32(data);
        assertEq(rootHash, sha256(abi.encodePacked(dataB32)));
        */

        //bytes memory version = CBORDecoding.decodeMappingGetValue(cborSansSig, bytes("version"));
        //assertEq(string(abi.encodePacked(version)), "3");

        //assertEq(cid.length, bar);

    }

}
