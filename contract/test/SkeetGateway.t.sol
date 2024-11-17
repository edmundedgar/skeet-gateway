// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {BBS} from "../src/BBS.sol";
import {console} from "forge-std/console.sol";

contract SkeetGatewayTest is Test {
    SkeetGateway public gateway;
    BBS public bbs; // makes 0x2e234DAe75C793f67A35089C9d99245E1C58470b

    function setUp() public {
        gateway = new SkeetGateway();
        bbs = new BBS();
    }

    function testRealAddressRecovery() public {
        // Address for edmundedgar.unconsensus.com, recovered earlier by signing a message with the private key then running ecrecover on it
        address expect = address(0x69f2163DE8accd232bE4CD84559F823CdC808525);

        // Prepared earlier by doing:
        // bytes32 priv = // fill this from edmundedgar.unconsensus.com.sec
        // bytes32 hash = sha256("Signed by Ed");
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(priv), hash);

        // cborSansSig is the data that the PDS signs.
        // It's a CBOR representation of:
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
        bytes32 hash = sha256(cborSansSig);

        // sig from car file was 'd395a8c48c851c0ae8abe772d9fc33cac0619709ca2bcc5b60f7ff9e6ff7bf8363f68f57c10e0277403e800c5b9fd7c448f9816bf4ab878fd8148ceb24ef520b',
        // manually split it in half
        bytes32 r = 0xd395a8c48c851c0ae8abe772d9fc33cac0619709ca2bcc5b60f7ff9e6ff7bf83;
        bytes32 s = 0x63f68f57c10e0277403e800c5b9fd7c448f9816bf4ab878fd8148ceb24ef520b;

        uint8 v = 28;
        bool found = false;
        // for(uint8 v=0; v<255; v++) { } // Earlier we had to try all possible v values to find the one they used
        address signer = ecrecover(hash, v, r, s);
        assertEq(expect,  signer, "should recover the same signer"); 
    }

    function testAddressRecovery() public {

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 hash = sha256("Signed by Alice");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, hash);
        address signer = ecrecover(hash, v, r, s);
        assertEq(alice, signer);

        address expectedSigner = gateway.predictSignerAddress(hash, v, r, s);
        assertEq(expectedSigner, signer);
    }

    function test_Init() public {
        vm.recordLogs();

        string memory payload = '{"text": "0x2e234DAe75C793f67A35089C9d99245E1C58470b Hi from bsky later hopefully", "blah": "blah"}';
        //string memory payload = string.concat('{"text": "Hi from bsky later hopefully", "blah": "blah"}');
        // string memory payload = string.concat(string(abi.encodePacked(address(bbs))), ' Hi from bsky later hopefully');
        uint256[] memory offsets = new uint256[](2);
        offsets[0] = 10; // trims the stuff before the address
        offsets[1] = 81; // trims the stuff from the end of the comment

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 hash = sha256(bytes(payload));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, hash);
        address signer = ecrecover(hash, v, r, s);
        assertEq(alice, signer);

        address expectedSigner = gateway.predictSignerAddress(hash, v, r, s);
        assertEq(alice, expectedSigner);

        /*
        bytes memory data = hex"41";
        bytes memory sig = hex"42";
        uint8 v = 1;
        bytes32 r = hex"43";
        bytes32 s = hex"44";
        */

        //bytes32 root = bytes32(0);
        //bytes32 root = hash;
        bytes32[] memory proofHashes = new bytes32[](1);
        proofHashes[0] = hash; // should be the root hash

        assertNotEq(expectedSigner, address(0), "Signer not found");
        address expectedSafe = address(gateway.predictSafeAddress(hash, v, r, s));
        assertNotEq(expectedSafe, address(0), "expected safe empty");

        assertEq(address(gateway.signerSafes(expectedSigner)), address(0), "Safe not created yet");

        gateway.handleSkeet(payload, offsets, proofHashes, v, r, s);

        address createdSafe = address(gateway.signerSafes(expectedSigner));
        assertNotEq(createdSafe, address(0), "Safe now created");
        assertEq(createdSafe, expectedSafe, "Safe not expected address");

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);

        assertEq(entries[0].topics[1], bytes32(uint256(uint160(expectedSigner))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(expectedSafe))));

        assertEq(gateway.signerSafes(expectedSigner).owner(), address(gateway));

        assertEq(bbs.messages(createdSafe), "Hi from bsky later hopefully");
        assertNotEq(bbs.messages(createdSafe), "oinK");

    }

}
