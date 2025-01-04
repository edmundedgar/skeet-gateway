// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DidFormats} from "../src/DidFormats.sol";

contract DidFormatClient is DidFormats {

    function callDidKeyToBytes(string calldata pubkey) public pure returns (bytes memory) {
        return didKeyToBytes(string(pubkey[9:]));
    }
}

contract DidVerifierTest is Test{

    DidFormatClient client;
    function setUp() public {
        client= new DidFormatClient();
    }

    function testSigToBase64UrlEncoded() public view {
        string memory origEncodedSig = "2-G4D9YXFCB6LTrvalq23o7vey1W7KcSVDf-IkfU_x8AFAVUn2VtxSXTtCMr5tAe72KyPSzzw0kaV0M88JuCEA";
        bytes memory decodedSig = bytes(hex"dbe1b80fd61714207a2d3aef6a5ab6de8eef7b2d56eca7125437fe2247d4ff1f001405549f656dc525d3b4232be6d01eef62b23d2cf3c3491a57433cf09b8210");
        bytes memory encodedSig = client.sigToBase64URLEncoded(decodedSig);
        assertEq(keccak256(encodedSig), keccak256(bytes(origEncodedSig)), "sig should match after reencoding");
    }

    function testDidKeyToBytes() public view {
        string memory origEncodedPubkey = "did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg";
        bytes memory origDecodedPubkey = bytes(hex"0325f4891e63128b8ab689e862b8e11428f24095e3e57b9ea987eb70d1b59af9df");
        bytes memory decodedPubkey = client.callDidKeyToBytes(origEncodedPubkey);
        assertEq(keccak256(origDecodedPubkey), keccak256(bytes(decodedPubkey)), "pubkey should decode to what we prepared earlier");
    }

    function testBase32CidToSha256() public view {
        bytes memory origDecodedCidSha = bytes(hex"7e32bcc27e0e9b889c1f930b1c7a3514dfc0d2983e59e3a7bb619c00d6ca5b1c");
        string memory encodedCid = "bafyreid6gk6me7qotoejyh4tbmohuniu37anfgb6lhr2po3btqannss3dq";

        // eg https://cid.ipfs.tech/?ref=filebase.com#bafyreid6gk6me7qotoejyh4tbmohuniu37anfgb6lhr2po3btqannss3dq


        // "decoded": "0x342b7199d6ea83667d1529e48c6a9da2b72213c4774ce644d42e16e5e4ff58c6",
        // "encoded": "bafyreibufnyztvxkqnth2fjj4sggvhncw4rbhrdxjttejvboc3s6j72yyy"

    }

    //bytes32 hash = keccak256(publicKey);
    //return address(uint160(uint256(hash)));


}
