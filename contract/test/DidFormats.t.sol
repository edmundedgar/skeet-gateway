// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DidFormats} from "../src/DidFormats.sol";

contract DidFormatClient is DidFormats {}

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
            hex"8fe3769f5055088b448ca064bcecd7b6844239c355c98d4556d5c9c8c522de784fdc4cd480dc7b99d505243ec026409569a69842dbae649940cf7e8496efa31d"
        );
        string memory recoveredDidKey = client.pubkeyBytesToDidKey(decompressedPubkey);
        //console.log(recoveredDidKey);
        //console.log(origEncodedDidKey);
        assertEq(
            keccak256(bytes(origEncodedDidKey)),
            keccak256(bytes(recoveredDidKey)),
            "did key should encode to what we prepared earlier"
        );
    }

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

    function testGenesisHashToDidKey() public view {
        // The initial update of did:plc:pyzlzqt6b2nyrha7smfry6rv
        bytes memory genesis = bytes(
            hex"a7637369677856322d473444395958464342364c547276616c7132336f377665793157374b63535644662d496b66555f783841464156556e3256747853585474434d723574416537324b7950537a7a77306b6156304d38384a754345416470726576f664747970656d706c635f6f7065726174696f6e687365727669636573a16b617470726f746f5f706473a264747970657819417470726f746f506572736f6e616c4461746153657276657268656e64706f696e747368747470733a2f2f62736b792e736f6369616c6b616c736f4b6e6f776e417381781c61743a2f2f65646d756e6465646761722e62736b792e736f6369616c6c726f746174696f6e4b6579738278396469643a6b65793a7a513373686843475571444b6a53747a754478506b54784e36756a64645034526b454b4a4a6f754a4752526b614c47626778396469643a6b65793a7a51337368704b6e62645078336733436d5066356352565450653148745377566e356973683377536e44505143624c4a4b73766572696669636174696f6e4d6574686f6473a167617470726f746f78396469643a6b65793a7a51337368586a486569427552434b6d4d33366375596e6d3759454d7a68476e436d437957393273524a39707269625346"
        );
        bytes32 genesisHash = sha256(genesis);
        bytes32 did = client.genesisHashToDidKey(genesisHash);
        assertEq(did, bytes32(bytes("did:plc:pyzlzqt6b2nyrha7smfry6rv")));
    }
}
