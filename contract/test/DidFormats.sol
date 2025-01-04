// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DidFormats} from "../src/DidFormats.sol";

contract DidFormatClient is DidFormats {

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

    }

    //bytes32 hash = keccak256(publicKey);
    //return address(uint160(uint256(hash)));


}
