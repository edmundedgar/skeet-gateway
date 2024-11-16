// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {BBS} from "../src/BBS.sol";
import {console} from "forge-std/console.sol";

contract SkeetGatewayTest is Test {
    SkeetGateway public gateway;
    BBS public bbs;

    function setUp() public {
        gateway = new SkeetGateway();
        bbs = new BBS();
    }

    function testAddressRecovery() public {

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 hash = keccak256("Signed by Alice");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, hash);
        address signer = ecrecover(hash, v, r, s);
        assertEq(alice, signer);

        address expectedSigner = gateway.predictSignerAddress(hash, v, r, s);
        assertEq(expectedSigner, signer);
    }

    function test_Init() public {
        vm.recordLogs();

        //string memory payload = string.concat('{"text": "', string(abi.encodePacked(address(bbs))), ' Hi from bsky later hopefully", "blah": "blah"}');
        string memory payload = string.concat(string(abi.encodePacked(address(bbs))), ' Hi from bsky later hopefully');

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 hash = keccak256(bytes(payload));
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

        uint256[] memory offsets = new uint256[](3);

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

        assertEq(bbs.messages(createdSafe), payload);
        assertNotEq(bbs.messages(createdSafe), "oinK");

    }

}
