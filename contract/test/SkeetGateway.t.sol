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

    struct SkeetProof {
        bytes commitNode;
        bytes content;
        string did;
        uint256[] nodeHints;
        bytes[] nodes;
        bytes32 r;
        string rkey;
        bytes32 s;
    }

    function setUp() public {
        gateway = new SkeetGateway();
        bbs = new BBS();
    }
    
    function testMerkleProvenRootHash() public {
        // Given a hash of the dataNode, crawl up the tree and give me a root hash that I expect to find in the Sig Node
        // For each record we should have a hint which is either:
        // For node 0 (data node): 
        // - index+1 of the entry where we will find our hash in the data field
        // For other nodes (intermediate nodes):
        // - 0 for the l record
        // - index+1 for the e record where we should find our hash in the t field
        string memory json = vm.readFile(string.concat(vm.projectRoot(),"/test/fixtures/ss.json"));
        bytes memory data = vm.parseJson(json);
        SkeetProof memory proof = abi.decode(data, (SkeetProof));

        // Check the value is in the data node and recover the rkey
        (bytes32 rootHash, string memory rkey) = gateway.merkleProvenRootHash(sha256(proof.content), proof.nodes, proof.nodeHints);
        //string memory rkey = gateway.dataNodeRecordKeyForCID(sha256(proof.content), proof.dataNode, proof.dataNodeHint);
        string memory full_key = string.concat("app.bsky.feed.post/", proof.rkey);
        assertEq(keccak256(abi.encode(rkey)), keccak256(abi.encode(full_key)));

        gateway.assertCommitNodeContainsData(rootHash, proof.commitNode);

    }

    function testActualSkeetBBSPost() public {
        // Given a hash of the dataNode, crawl up the tree and give me a root hash that I expect to find in the Sig Node
        // For each record we should have a hint which is either:
        // - 0 for the l record
        // - 1 for the e record where we should find the t
        string memory json = vm.readFile(string.concat(vm.projectRoot(),"/test/fixtures/car_files_cannot_hurt_you.json"));
        bytes memory data = vm.parseJson(json);
        SkeetProof memory proof = abi.decode(data, (SkeetProof));

        uint256[] memory offsets = new uint256[](2);
        offsets[0] = 10; // trims the stuff before the address
        offsets[1] = 81; // trims the stuff from the end of the comment

        gateway.handleSkeet(proof.content, proof.nodes, proof.nodeHints, proof.commitNode, 28, proof.r, proof.s);
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

/*
        {
  verificationMethod: {
    id: 'did:plc:mtq3e4mgt7wyjhhaniezej67#atproto',
    type: 'Multikey',
    controller: 'did:plc:mtq3e4mgt7wyjhhaniezej67',
    publicKeyMultibase: 'zQ3shXE71bKUBKFobEBdqa2oys5gZZb5pTGkZRoaW8M9PAgFY'
  },
  query: {
    did: 'did:plc:mtq3e4mgt7wyjhhaniezej67',
    collection: 'app.bsky.feed.post',
    rkey: '3laydu3mgac2v'
  },
  merkleData: {
    rootSig: "d395a8c48c851c0ae8abe772d9fc33cac0619709ca2bcc5b60f7ff9e6ff7bf8363f68f57c10e0277403e800c5b9fd7c448f9816bf4ab878fd8148ceb24ef520b",
    rootCbor: "a56364696478206469643a706c633a6d74713365346d67743777796a6868616e69657a656a3637637265766d336c61796b6c746f73703232716464617461d82a5825000171122066da6655bf8da79b69a87299cf170fed8497fa3059379dc4a8bfe1e28cab5d936470726576f66776657273696f6e03",
    treeCids: [
      "017112203bb70fb18797262742741ffca10f82867cc7997eac6666d312be7757d53d0a7b",
      "0171122066da6655bf8da79b69a87299cf170fed8497fa3059379dc4a8bfe1e28cab5d93",
      "017112206e7335ed248edae3ed49d47b88a5fcad2985e15f416f8ae23a49dfc1231aeb91",
      "01711220876175f10e6458ab735dbacf697d9caacec33486bc4a633be553fd43531012f5",
      "01711220f4b863bcbfe27980f02288eeeb45ae58b4083c1926827e2815bc523ab889309f",
      "017112206d51f125727763752e073d9301892fbddaa4cc6090d5fff9af7d49106b92d457"
    ],
    treeCbors: [
      "a66364696478206469643a706c633a6d74713365346d67743777796a6868616e69657a656a3637637265766d336c61796b6c746f7370323271637369675840d395a8c48c851c0ae8abe772d9fc33cac0619709ca2bcc5b60f7ff9e6ff7bf8363f68f57c10e0277403e800c5b9fd7c448f9816bf4ab878fd8148ceb24ef520b6464617461d82a5825000171122066da6655bf8da79b69a87299cf170fed8497fa3059379dc4a8bfe1e28cab5d936470726576f66776657273696f6e03",
      "a2616585a4616b58236170702e62736b792e67726170682e666f6c6c6f772f336b77767534737665647332346170006174d82a58250001711220b000383f1466f65b0a02da763f46cf0e4510d832f6c609a9df56db73b81259376176d82a582500017112205cd7382608fb47afda979840cf0024b3d2d2e9e43448713909e998b6a1849490a4616b486679656a776332346170181b6174d82a58250001711220b295211bc0bfc8a6c8404f4877e96c37b25272c85e4942a29b178d26803f13996176d82a5825000171122017428f68c9c19f59b08b4b2d71ce96e04cdaf6139b94baf0a2c5ee51aa74493fa4616b486d77686f6e3232346170181b6174d82a58250001711220752be9d63155323fc5ce8753bdb5832fc7f5ad762c4e37944a6de84bbb9516876176d82a582500017112200fe8a27c597fcc6059888660b321e473bdaa94b45d0a702f3bd05e013ff17564a4616b486e337667376332346170181b6174d82a58250001711220ff7f6bd81b38a383101aec250c290ec6cd33555baf1e644f4b6d9b60a2e1fb856176d82a58250001711220a9f192fea504ecf8ae900d2a4f9f37551865132ae50bf680ac1687636afee7e1a4616b486f797875373232346170181b6174d82a582500017112204afcab072750efa8755714ca8477b35e871b71856a329c9973c4b94b7a4c98986176d82a58250001711220c46c805c774dcd3eaf4f90cef5e63f1f2a53f9c6bdb14b7397e736678b54dc97616cd82a582500017112206e7335ed248edae3ed49d47b88a5fcad2985e15f416f8ae23a49dfc1231aeb91",
      "a2616584a4616b58236170702e62736b792e67726170682e666f6c6c6f772f336b77767473726366736332346170006174d82a58250001711220232061c4165ce246d7f0b997b4a4212a0355faadf93fdecd64fca89db1d7bd9e6176d82a58250001711220181c3cddd15732e2a37c4455038c71ba75c1d5ca1850f78086d7bf29b490f7cba4616b487470346b797332346170181b6174d82a5825000171122096273e2ef4796b720c8e9f12292dfde8ce593a898ddd3c4c8d6d94c292736d1b6176d82a58250001711220783771b7cd8110221784049f5a1aba5ca85f660433233adb67f2045f1c05af72a4616b47773332356332346170181c6174d82a58250001711220f597936ae0b3636bcd64599dce397d33bcd1d0983af996b5ed02bdad5a6234156176d82a5825000171122009a988e6d9558a6e503e6f3194693953308be2fcbbb8831147b062b308cb291aa4616b497533366f62716332346170181a6174d82a58250001711220d5aa58f18245f4332affc4ce8fad050370013160f764027ea5897184caeb62446176d82a582500017112208e3047b78dad736d03697eedf8f49570c614c4e49cb89d86bd85d8351436e15d616cd82a58250001711220876175f10e6458ab735dbacf697d9caacec33486bc4a633be553fd43531012f5",
      "a261658fa4616b58206170702e62736b792e666565642e6c696b652f336b77793265767961626b32346170006174d82a58250001711220d79485e9d78c6b5c611c46352eb43d09283262efc7d7330cca0192501780e4716176d82a58250001711220d07a75d28a5f05f06bbc624a7778713cb26a7a3d275f246c0522e2a2372885d0a4616b4b78353561707135656332346170156174d82a5825000171122071ba1a031bb8ccc7989b028a58555667bb0ac797e43dc79cf3beae00c6b7d8626176d82a58250001711220f06d947dab3e4a53246d64ca139cf697b97cf78477e9dce60c70a017a86f4cdda4616b4968356d6679776b32346170176174d82a58250001711220372be56299a081d7b4f32a6b096664c447d9ebe4459dcdcbaca7ab39c7eebf7c6176d82a582500017112202ebf1579b239e9f86c419af518cd566c14f9a1ca401517739d5f46c51857d840a4616b4a617036773771747332346170166174d82a58250001711220e8a95c55c128235a019ea71f487e19964ac190a7e7cad848d30c6d8b0392e6cd6176d82a582500017112204017a8f3a2f7ed915fb39c1ea353b50ec9a21596de2f7df29158c2b29452dc7ca4616b4a626374633478726b32346170166174d82a582500017112204841e142038dd36a42f7f7eda2815ee89b6d76ff6e7655072c4a71e05a7820466176d82a58250001711220c5b7810955b7ad9fe798613400d49853b02e4dea47568d29c83fd1589485ff42a4616b4a6478796e7432627332346170166174f66176d82a58250001711220bf06915e9710d746cebd939b08d1b7e144a92caf4fa9aecf6219340f148c4019a4616b497a78657a6f363232346170176174d82a58250001711220689b68944b3a6218c5805b663557ef71e51f72757253d7caa745e0045c34cf3a6176d82a582500017112205cbe591b994b30ebab1fba98eeed1c8ec38f5539cd8ff5ccad2d6066bd9a8f4fa4616b4a6a686963716b676332346170166174d82a5825000171122008ef90a042740a2704cf7661737c0f2a617b3c42f8453303718ca793ee2438206176d82a58250001711220867b815f5eba606a9a0c1978c2a96e814392d1b14d15be9194e4051f6a9e2147a4616b52706f73742f336c376665787a6e677432326f61700e6174d82a58250001711220f4b863bcbfe27980f02288eeeb45ae58b4083c1926827e2815bc523ab889309f6176d82a58250001711220d86efe1c0f93f8a04db7e336d3d57557bea2411bb0abf744ef18afe3ff4aaab3a4616b581a67726170682e666f6c6c6f772f336b77767472636237727332346170096174d82a58250001711220e8b3d1b92fd9faab603dfd905ac0991d6e6b8663e66e7dbecc1ed289dd79a8396176d82a58250001711220808017e4fb3917a300958db284b978eb62fa35fa445b5e6eab212137f3426b40a4616b47696e6f717332346170181c6174d82a5825000171122024e82389757936fd12c1d3741ebde9aea376ddf842d5d6b5d9fa48e69ce0554d6176d82a58250001711220e3769648c8205b8455e00bee4b7572e4ff92406f271d73ab8e101a4cb7524780a4616b47706b64636332346170181c6174d82a58250001711220f333dcd40a9195dedee3014aef64c76be9eeccf6ee419e891b1a2e13256286566176d82a58250001711220e71cb47506907a81d7a80d52bc117db1e077d4aa698f564db9fa747cee0215b3a4616b47736377623232346170181c6174d82a58250001711220910498efc865b41baa1b39b3001dd81f5552663a7bc0f22847b0a8ce90d51b106176d82a582500017112202fd0be4a7f0bf991b4e76b25ccc0c08b04a1643d205862054752c5b726c9f9dda4616b47797872727332346170181c6174d82a5825000171122025a005ff217b66a70fc32d473fbb5ed7213f172e74c38982cc964e3d504cda686176d82a582500017112206e8e4b3e410d0f6950bd12a6a2df3a969ac595942cd21ea7bd20a2c1f4ce8fc6a4616b487361346a346b32346170181b6174d82a5825000171122071ef0339b2effbb272173feaca40d8ba7f7d424bdbec7964d9b7a0ff18f7f62c6176d82a5825000171122088a7a7cbbde346911b14a8e8b4304013fdc67a9cda03077f7134edbbbf614e08616cd82a5825000171122046ec1d42dc9317f90ac865a065c8053e9d656d475831bb7bb3640a992b8a95f0",
      "a2616586a4616b58206170702e62736b792e666565642e706f73742f336c61793263706777353232766170006174f66176d82a58250001711220f12c9d56de3c2455a4588a818489b7b29125dcbf8312eee31d49082092ec80c2a4616b496475336d67616332766170176174f66176d82a582500017112206d51f125727763752e073d9301892fbddaa4cc6090d5fff9af7d49106b92d457a4616b547265706f73742f336b777736773779706173323461700e6174f66176d82a58250001711220ba7e5a8635be6208ea13c2ce09f81ab27feb6690740342a994117ad11d13f553a4616b4a793276667663666b3234617018186174d82a58250001711220bd95f96f2f1ae89f33cd79eec6ce8f7a036cda26c476f779bd602ce84219196e6176d82a58250001711220d5c48e2b88b3f26c98ffddb7d5c9d4f8e65aaa8a33c2cb43f666706f49bfdfb3a4616b4b78373678333479343232346170176174d82a58250001711220aed62b3da09961d039f3e14c1cf3648a44fb77a94653224d0045fe07d1f3052c6176d82a58250001711220659d834ba9a882e5af0a8e5aceb5573f1a139e5e0f14c809f3206f833c80eca8a4616b581a67726170682e666f6c6c6f772f336b7776746a773564703232346170096174d82a58250001711220793ff8bce08a2771b092f6e37b8ca895741e8e6726558a0325e380390a74259a6176d82a58250001711220834ebbe3926bd86293e298a8c86ba65cd569431403810336626268290cad43f2616cf6",
      "a4647465787478196361722066696c65732063616e6e6f74206875727420796f75652474797065726170702e62736b792e666565642e706f7374656c616e67738162656e696372656174656441747818323032342d31312d31355431323a31303a33322e3031345a"
    ]
  }
}
*/

    }
/*
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
        */

}
