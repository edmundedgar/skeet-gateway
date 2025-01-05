// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DidFormats} from "../src/DidFormats.sol";

import {Base58} from "@base58-solidity/contracts/Base58.sol";

contract DidFormatClient is DidFormats {
    function callPubkeyBytesToDidKey(bytes calldata pubkey) public view returns (string memory) {
        return pubkeyBytesToDidKey(pubkey[0:33]);
    }
}

contract DidFormatsTest is Test {
    DidFormatClient client;

    function setUp() public {
        client = new DidFormatClient();
    }

    function testSigToBase64UrlEncoded() public view {
        string memory origEncodedSig =
            "2-G4D9YXFCB6LTrvalq23o7vey1W7KcSVDf-IkfU_x8AFAVUn2VtxSXTtCMr5tAe72KyPSzzw0kaV0M88JuCEA";
        bytes memory decodedSig = bytes(
            hex"dbe1b80fd61714207a2d3aef6a5ab6de8eef7b2d56eca7125437fe2247d4ff1f001405549f656dc525d3b4232be6d01eef62b23d2cf3c3491a57433cf09b8210"
        );
        bytes memory encodedSig = client.sigToBase64URLEncoded(decodedSig);
        assertEq(keccak256(encodedSig), keccak256(bytes(origEncodedSig)), "sig should match after reencoding");
    }

    function testPubkeyBytesToDidKey() public view {
        string memory origEncodedDidKey = "did:key:zQ3shpKnbdPx3g3CmPf5cRVTPe1HtSwVn5ish3wSnDPQCbLJK";
        bytes memory decompressedPubkey = bytes(
            hex"038fe3769f5055088b448ca064bcecd7b6844239c355c98d4556d5c9c8c522de784fdc4cd480dc7b99d505243ec026409569a69842dbae649940cf7e8496efa31d"
        );
        string memory recoveredDidKey = client.callPubkeyBytesToDidKey(decompressedPubkey);
        //console.log(recoveredDidKey);
        //console.log(origEncodedDidKey);
        assertEq(
            keccak256(bytes(origEncodedDidKey)),
            keccak256(bytes(recoveredDidKey)),
            "did key should encode to what we prepared earlier"
        );
    }

    /*
    function testDidKeyToBytes() public view {
        string memory origEncodedPubkey = "did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg";
        bytes memory origDecodedPubkey = bytes(hex"0325f4891e63128b8ab689e862b8e11428f24095e3e57b9ea987eb70d1b59af9df");
        bytes memory decodedPubkey = client.callDidKeyToBytes(origEncodedPubkey);
        assertEq(
            keccak256(origDecodedPubkey),
            keccak256(bytes(decodedPubkey)),
            "pubkey should decode to what we prepared earlier"
        );
    }

    function testDidKeyToAddress() public view {
        string memory origEncodedPubkey = "did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg";
        address origAddr = address(0x52FC60077f9712b9D6bd927738edBFB41de9A78E);
        assertEq(
            origAddr, client.callDidKeyToAddress(origEncodedPubkey), "address should match what we checked in python"
        );
    }
    */

    function testBase32CidToSha256() public view {
        bytes32 origDecodedCidSha = 0x7e32bcc27e0e9b889c1f930b1c7a3514dfc0d2983e59e3a7bb619c00d6ca5b1c;
        string memory origEncodedCid = "bafyreid6gk6me7qotoejyh4tbmohuniu37anfgb6lhr2po3btqannss3dq";
        string memory encodedCid = client.sha256ToBase32CID(origDecodedCidSha);
        assertEq(keccak256(bytes(origEncodedCid)), keccak256(bytes(encodedCid)), "should get expected cid back");

        bytes32 origDecodedCidSha2 = 0x342b7199d6ea83667d1529e48c6a9da2b72213c4774ce644d42e16e5e4ff58c6;
        string memory origEncodedCid2 = "bafyreibufnyztvxkqnth2fjj4sggvhncw4rbhrdxjttejvboc3s6j72yyy";
        string memory encodedCid2 = client.sha256ToBase32CID(origDecodedCidSha2);
        assertEq(
            keccak256(bytes(origEncodedCid2)),
            keccak256(bytes(encodedCid2)),
            "should get expected cid back this time too"
        );
    }
}
