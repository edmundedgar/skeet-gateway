// SPDe-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DagCborNavigator} from "../src/DagCborNavigator.sol";
import {console} from "forge-std/console.sol";

bytes constant CBOR_HEADER_TEXT_5 = bytes(hex"6474657874"); // text, "text"
bytes constant CBOR_HEADER_TYPE_6 = bytes(hex"652474797065"); // text, "$type"

bytes constant CBOR_HEADER_VERSION_8 = bytes(hex"6776657273696f6e");
bytes constant CBOR_HEADER_DATA_5 = bytes(hex"6464617461"); // text, data

// Workaround for issues making forge handle calldata
contract DagCborNavigatorClient {
    function firstMatch(
        bytes calldata cbor,
        DagCborNavigator.DagCborSelector[] memory selector,
        uint256 currentLevel,
        uint256 cursor
    ) external returns (uint256, uint256) {
        return DagCborNavigator.firstMatch(cbor, selector, currentLevel, cursor);
    }

    function indexOfMappingField(bytes calldata cbor, bytes memory fieldHeader, uint256 cursor)
        external
        pure
        returns (uint256)
    {
        return DagCborNavigator.indexOfMappingField(cbor, fieldHeader, cursor);
    }

    function indexToInsertMappingField(bytes calldata cbor, bytes memory fieldHeader, uint256 cursor)
        external
        pure
        returns (uint256)
    {
        return DagCborNavigator.indexToInsertMappingField(cbor, fieldHeader, cursor);
    }

    function indexOfFieldPayloadEnd(bytes calldata cbor, uint256 byteIndex) external pure returns (uint256) {
        return DagCborNavigator.indexOfFieldPayloadEnd(cbor, byteIndex);
    }

    function parseCborHeader(bytes calldata cbor, uint256 byteIndex) external pure returns (uint8, uint64, uint256) {
        return DagCborNavigator.parseCborHeader(cbor, byteIndex);
    }
}

contract DagCborNavigatorTest is Test {
    bytes cborMap;
    bytes cborWithCIDs;
    DagCborNavigatorClient client;

    function setUp() public {
        client = new DagCborNavigatorClient();

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

        // This is a commit node from one of the fixtures
        cborWithCIDs = bytes(
            hex"a56364696478206469643a706c633a6d74713365346d67743777796a6868616e69657a656a3637637265766d336c63767332696d73756b32666464617461d82a5825000171122020b90507550beb6a0c2d031c2ffca2ce1c1702933a47070ddcdaf3cc1879a9546470726576f66776657273696f6e03"
        );
    }

    function testIndexOfFieldPayloadEndSimple() public view {
        uint256 payloadEnd = client.indexOfFieldPayloadEnd(cborMap, 1);
        assertEq(payloadEnd, 1 + 1 + 11);

        uint256 cursor = 1 + 2 + 11 - 1;
        payloadEnd = client.indexOfFieldPayloadEnd(cborMap, cursor);
    }

    function testIndexOfFieldPayloadEndCID() public view {
        // Test on the data CID
        // The data CID including headers starts at 62:
        // d82a5825 (4 bytes)
        // 00017112202 (5 bytes)
        // 0b90507550beb6a0c2d031c2ffca2ce1c1702933a47070ddcdaf3cc1879a95464 (32 bytes)

        // Find the start
        // This incidentally tests everything before the CID in the data as indexOfMappingField uses indexOfFieldPayloadEnd
        uint256 start = client.indexOfMappingField(cborWithCIDs, CBOR_HEADER_DATA_5, 1);
        assertEq(62, start);

        uint8 maj;
        uint64 extra; // should be the length
        uint256 payloadStart;
        (maj, extra, payloadStart) = client.parseCborHeader(cborWithCIDs, start);
        assertEq(extra, 5 + 32);

        assertEq(maj, 6);

        uint256 payloadEnd = client.indexOfFieldPayloadEnd(cborWithCIDs, start);
        assertEq(62 + 4 + 5 + 32, payloadEnd);
    }

    function testIndexOfMappingField() public view {
        uint256 cursor = 1 + 1 + 11 + 1 + 1 + 11;
        bytes memory largeFieldText = bytes(hex"6b6c617267654e756d626572");
        uint256 index = client.indexOfMappingField(cborMap, largeFieldText, 1);
        assertEq(index, cursor);
    }

    function testIndexOfMappingFieldMissingField() public {
        bytes memory oink = bytes(hex"6F696E6B");
        vm.expectRevert();
        client.indexOfMappingField(cborMap, oink, 1);
    }

    function testIndexToInsertMappingFieldMid() public view {
        // This has the proper dag-cbor field ordering, unlike other tests here
        // A5                       # map(5)
        //    61                    # text(1)
        //       61                 # "a"
        //    65                    # text(5)
        //       6461746131         # "data1"
        //    61                    # text(1)
        //       62                 # "b"
        //    66                    # text(6)
        //       646174613232       # "data22"
        //    61                    # text(1)
        //       7A                 # "z"
        //    67                    # text(7)
        //       64617461333333     # "data333"
        //    62                    # text(2)
        //       6131               # "a1"
        //    68                    # text(8)
        //       6461746134343434   # "data4444"
        //    63                    # text(3)
        //       7A6F6F             # "zoo"
        //    69                    # text(9)
        //       646174613535353535 # "data55555"
        //
        bytes memory dagCborMap = bytes(
            hex"A56161656461746131616266646174613232617A6764617461333333626131686461746134343434637A6F6F69646174613535353535"
        );

        // this is the start of the value field so we back up the length of the header (3) to get to the name field
        uint256 a1idx = client.indexOfMappingField(dagCborMap, bytes(hex"626131"), 1) - 3;

        // 626130 "a0" should slot in where a1 went
        uint256 idx = client.indexToInsertMappingField(dagCborMap, bytes(hex"626130"), 1);
        assertEq(a1idx, idx, "same length should slot in based on ascii sort order");
    }

    function testIndexToInsertMappingFieldEnd() public view {
        // same cbor as previous test
        bytes memory dagCborMap = bytes(
            hex"A56161656461746131616266646174613232617A6764617461333333626131686461746134343434637A6F6F69646174613535353535"
        );

        uint256 endIdx = dagCborMap.length;

        // 68                  # text(8)
        // 386C657474657273 # "8letters"

        uint256 idx = client.indexToInsertMappingField(dagCborMap, bytes(hex"68386C657474657273"), 1);
        assertEq(endIdx, idx, "something that sorts after all fields should be at the end of the mapping");
    }

    function testIndexOfMappingFieldSkippingInnerMapping() public view {
        // {"a": 1, "b": 2, "c": {"c1": 9, "c2": 9, "c3": 7}, "target": 123, "more": "data"}

        // A5                 # map(5)
        //    61              # text(1)
        //       61           # "a"
        //    01              # unsigned(1)
        //    61              # text(1)
        //       62           # "b"
        //    02              # unsigned(2)
        //    61              # text(1)
        //       63           # "c"
        //    A3              # map(3)
        //       62           # text(2)
        //          6331      # "c1" [2 bytes]
        //       09           # unsigned(9)
        //       62           # text(2)
        //          6332      # "c2" [2 bytes]
        //       09           # unsigned(9)
        //       62           # text(2)
        //          6333      # "c3" [2 bytes]
        //       07           # unsigned(7)
        //    66              # text(6)
        //       746172676574 # "target" [7 bytes]
        //    18 7B           # unsigned(123) [2 bytes]
        //    64              # text(4)
        //       6D6F7265     # "more" [4 bytes]
        //    64              # text(4)
        //       64617461     # "data" [4 bytes]

        bytes memory nestedCbor =
            hex"A56161016162026163A362633109626332096263330766746172676574187B646D6F72656464617461";
        uint256 expectIndex = 29; // end of "target" text
        uint256 index = client.indexOfMappingField(nestedCbor, bytes(hex"66746172676574"), 1);
        assertEq(index, expectIndex);
    }

    function testIndexToInsertMappingField() public view {
        // same cbor as previous
        bytes memory nestedCbor =
            hex"A56161016162026163A362633109626332096263330766746172676574187B646D6F72656464617461";
        uint256 expectIndex = 29 - 7; // end of target text - target header
        // "zoo" should sort where "target" would start
        uint256 index = client.indexToInsertMappingField(nestedCbor, bytes(hex"637A6F6F"), 1);
        assertEq(index, expectIndex, "zoo should sort where target would go");
    }

    function testIndexOfMappingFieldWithCIDs() public view {
        // The value we want is the version last byte (3)
        uint256 expectIndex = cborWithCIDs.length - 1;
        uint256 index = client.indexOfMappingField(cborWithCIDs, CBOR_HEADER_VERSION_8, 1);
        assertEq(index, expectIndex);
    }

    function testMappingSelector() public {
        // {"a": 1, "b": 2, "c": {"c1": 9, "c2": 9, "c3": 7}, "target": 123, "more": "data"}
        // See cbor.me detail in testIndexOfMappingFieldSkippingInnerMapping

        bytes memory nestedCbor =
            hex"A56161016162026163A362633109626332096263330766746172676574187B646D6F72656464617461";
        uint256 expectIndex = 29; // end of "target" text
        uint256 index = client.indexOfMappingField(nestedCbor, bytes(hex"66746172676574"), 1);
        assertEq(index, expectIndex);

        uint256 foundCursor;

        DagCborNavigator.DagCborSelector[] memory simpleSelector = new DagCborNavigator.DagCborSelector[](1);
        simpleSelector[0] = DagCborNavigator.createSelector("b");
        (foundCursor,) = client.firstMatch(nestedCbor, simpleSelector, 0, 0);
        assertTrue(foundCursor > 0, "b index should be found");
        assertEq(6, foundCursor, "Index 1 cursor should start where the b starts");

        DagCborNavigator.DagCborSelector[] memory simpleSelectorC = new DagCborNavigator.DagCborSelector[](1);
        simpleSelectorC[0] = DagCborNavigator.createSelector("c");
        (foundCursor,) = client.firstMatch(nestedCbor, simpleSelectorC, 0, 0);
        assertTrue(foundCursor > 0, "c index should be found");
        //assertEq(9, start, "c index cursor should start where the c starts");
    }

    function testMappingSelectorPrefix() public {
        // {"a": 1, "b": 2, "c": {"c1": 9, "c2": 9, "c3": 7}, "target": 123, "more": "data"}
        // See cbor.me detail in testIndexOfMappingFieldSkippingInnerMapping

        bytes memory nestedCbor =
            hex"A56161016162026163A362633109626332096263330766746172676574187B646D6F72656464617461";
        uint256 expectIndex = 29; // end of "target" text
        uint256 index = client.indexOfMappingField(nestedCbor, bytes(hex"66746172676574"), 1);
        assertEq(index, expectIndex);

        uint256 foundCursor;

        DagCborNavigator.DagCborSelector[] memory simpleSelector = new DagCborNavigator.DagCborSelector[](1);
        simpleSelector[0] = DagCborNavigator.createSelector("b");
        (foundCursor,) = client.firstMatch(nestedCbor, simpleSelector, 0, 0);
        assertTrue(foundCursor > 0, "b index should be found");
        assertEq(6, foundCursor, "Index 1 cursor should start where the b starts");

        DagCborNavigator.DagCborSelector[] memory simpleSelectorC = new DagCborNavigator.DagCborSelector[](1);
        simpleSelectorC[0] = DagCborNavigator.createSelector("c");
        (foundCursor,) = client.firstMatch(nestedCbor, simpleSelectorC, 0, 0);
        assertTrue(foundCursor > 0, "c index should be found");
        //assertEq(9, start, "c index cursor should start where the c starts");
    }

    function testMappingSelectorAfterMapping() public {
        // {"a": 1, "b": 2, "c": {"c1": 9, "c2": 9, "c3": 7}, "target": 123, "more": "data"}
        // See cbor.me detail in testIndexOfMappingFieldSkippingInnerMapping

        bytes memory nestedCbor =
            hex"A56161016162026163A362633109626332096263330766746172676574187B646D6F72656464617461";

        uint256 foundCursor;
        DagCborNavigator.DagCborSelector[] memory simpleSelectorTarget = new DagCborNavigator.DagCborSelector[](1);
        simpleSelectorTarget[0] = DagCborNavigator.createSelector("target");
        (foundCursor,) = client.firstMatch(nestedCbor, simpleSelectorTarget, 0, 0);
        assertTrue(foundCursor > 0, "target index should be found");
        //assertEq(9, start, "c index cursor should start where the c starts");
    }

    function testArraySelector() public {
        // 83            # array(3)
        //    61         # text(1)
        //       61      # "a"
        //    61         # text(1)
        //       62      # "b"
        //    A1         # map(1)
        //       61      # text(1)
        //          63   # "c"
        //       19 0141 # unsigned(321)"c"
        //
        bytes memory cbor = bytes(hex"8361616162a16163190141");

        uint256 foundCursor;

        DagCborNavigator.DagCborSelector[] memory simpleSelector = new DagCborNavigator.DagCborSelector[](1);
        simpleSelector[0] = DagCborNavigator.createSelector(1);
        (foundCursor,) = client.firstMatch(cbor, simpleSelector, 0, 0);
        assertTrue(foundCursor > 0, "Index 1 should be found");
        assertEq(3, foundCursor, "Index 1 cursor should start where the b header starts");

        DagCborNavigator.DagCborSelector[] memory simpleSelector0 = new DagCborNavigator.DagCborSelector[](1);
        simpleSelector0[0] = DagCborNavigator.createSelector(0);
        (foundCursor,) = client.firstMatch(cbor, simpleSelector0, 0, 0);
        assertTrue(foundCursor > 0, "Index 0 should be found");
        assertEq(1, foundCursor, "Index 0 cursor should start where the a header starts");

        DagCborNavigator.DagCborSelector[] memory simpleAnySelector = new DagCborNavigator.DagCborSelector[](1);
        simpleAnySelector[0] = DagCborNavigator.createSelector();
        (foundCursor,) = client.firstMatch(cbor, simpleAnySelector, 0, 0);
        assertTrue(foundCursor > 0, "Index 0 should be found");
        assertEq(1, foundCursor, "Index 0 cursor should start where the a header starts");

        DagCborNavigator.DagCborSelector[] memory indexValueSelector = new DagCborNavigator.DagCborSelector[](1);
        indexValueSelector[0] = DagCborNavigator.createSelector(1, bytes("b"));
        (foundCursor,) = client.firstMatch(cbor, indexValueSelector, 0, 0);
        assertTrue(foundCursor > 0, "Index 1 should be found");
        assertEq(3, foundCursor, "Index 1 cursor should start where the b header starts");
    }

    function testMatchSelector() public {
        bytes memory cbor = bytes(
            hex"a56474657874782840616e7377657276312e626f742e7265616c6974792e6574682059657320302e3030303320455448652474797065726170702e62736b792e666565642e706f7374656c616e67738162656e657265706c79a264726f6f74a263636964783b6261667972656964687134786f336e7534686b71733435347861787179723679766d65716577797365676c64756e6165616364333678716a71726563757269784661743a2f2f6469643a706c633a7534643576357a736c356a623279333376746668796a6f352f6170702e62736b792e666565642e706f73742f336c646f72747362693365323366706172656e74a263636964783b6261667972656964687134786f336e7534686b71733435347861787179723679766d65716577797365676c64756e6165616364333678716a71726563757269784661743a2f2f6469643a706c633a7534643576357a736c356a623279333376746668796a6f352f6170702e62736b792e666565642e706f73742f336c646f727473626933653233696372656174656441747818323032342d31322d31395432313a31333a32362e3936305a"
        );

        DagCborNavigator.DagCborSelector[] memory simpleSelector = new DagCborNavigator.DagCborSelector[](1);
        simpleSelector[0] = DagCborNavigator.createSelector("$type");
        // field starts at 108/2
        // title is 652474797065
        uint256 foundCursor;
        (foundCursor,) = client.firstMatch(cbor, simpleSelector, 0, 0);
        assertTrue(foundCursor > 0, "Found the match");
        assertEq(54, foundCursor, "start not expected");

        DagCborNavigator.DagCborSelector[] memory simpleMissingSelector = new DagCborNavigator.DagCborSelector[](1);
        simpleMissingSelector[0] = DagCborNavigator.createSelector("pants");
        (foundCursor,) = client.firstMatch(cbor, simpleMissingSelector, 0, 0);
        assertFalse(foundCursor > 0, "Absent selector returns false");

        DagCborNavigator.DagCborSelector[] memory simpleAnyMappingSelector = new DagCborNavigator.DagCborSelector[](1);
        simpleAnyMappingSelector[0] = DagCborNavigator.createSelector();
        (foundCursor,) = client.firstMatch(cbor, simpleAnyMappingSelector, 0, 0);
        assertTrue(foundCursor > 0, "any mapping selector returns the text field");
        assertEq(foundCursor, 1 + 1 + 4, "Any should match the text field");

        DagCborNavigator.DagCborSelector[] memory badSelector = new DagCborNavigator.DagCborSelector[](3);
        badSelector[0] = DagCborNavigator.createSelector("faucets");
        badSelector[1] = DagCborNavigator.createSelector("features");
        badSelector[2] = DagCborNavigator.createSelector("uri");

        // max 22 key length
        (foundCursor,) = client.firstMatch(cbor, badSelector, 0, 0);
        assertFalse(foundCursor > 0, "Nonsense match not found");
    }

    function testMultiSelector() public {
        // {'text': 'Will this question show up on sepolia reality.eth?  #fe8880c...0229f78\n\n⇒Answer', '$type': 'app.bsky.feed.post', 'facets': [{'index': {'byteEnd': 81, 'byteStart': 71}, 'features': [{'uri': 'https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0xfe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78', '$type': 'app.bsky.richtext.facet#link'}]}, {'index': {'byteEnd': 70, 'byteStart': 52}, 'features': [{'tag': 'fe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78', '$type': app.bsky.richtext.facet#tag'}]}], 'createdAt': '2024-12-19T21:08:48.000Z'}
        bytes memory cbor = bytes(
            hex"a46474657874785157696c6c2074686973207175657374696f6e2073686f77207570206f6e207365706f6c6961207265616c6974792e6574683f202023666538383830632e2e2e303232396637380a0ae28792416e73776572652474797065726170702e62736b792e666565642e706f73746666616365747382a265696e646578a26762797465456e64185169627974655374617274184768666561747572657381a26375726978e568747470733a2f2f7265616c6974792e6574682e6c696e6b2f6170702f23212f6e6574776f726b2f31313135353131312f636f6e74726163742f3078616633336463623665386335633464396464663537396635333033316235313464313934343963612f746f6b656e2f4554482f7175657374696f6e2f3078616633336463623665386335633464396464663537396635333033316235313464313934343963612d307866653838383063663932313230646431356334656636643838393761373835326233303863666366623037343162636431383339353137626230323239663738652474797065781c6170702e62736b792e72696368746578742e6661636574236c696e6ba265696e646578a26762797465456e64184669627974655374617274183468666561747572657381a263746167784066653838383063663932313230646431356334656636643838393761373835326233303863666366623037343162636431383339353137626230323239663738652474797065781b6170702e62736b792e72696368746578742e666163657423746167696372656174656441747818323032342d31322d31395432313a30383a34382e3030305a"
        );

        // field starts at 108/2
        // title is 652474797065
        uint256 foundCursor;
        uint256 end;

        DagCborNavigator.DagCborSelector[] memory goodSelector = new DagCborNavigator.DagCborSelector[](5);
        // mapping > facets > any item > features > any item > uri
        goodSelector[0] = DagCborNavigator.createTargetSelector("uri");
        goodSelector[1] = DagCborNavigator.createSelector();
        goodSelector[2] = DagCborNavigator.createSelector("features");
        goodSelector[3] = DagCborNavigator.createSelector();
        goodSelector[4] = DagCborNavigator.createSelector("facets");
        // TODO: Maybe nicer to run this as an array of strings then create the selectors dynamically eg
        //  ("facets", "*", "features", "*", "url=blah")

        (foundCursor, end) = client.firstMatch(cbor, goodSelector, 0, 0);
        assertTrue(foundCursor > 0, "Found the match");
        //bytes memory uri = bytes(cbor[foundCursor:end]);
        //console.log(string(uri));
        uint64 extra;
        uint256 cursor;
        (, extra, cursor) = client.parseCborHeader(cbor, foundCursor);
    }

    function testMultiSelector2() public {
        // {'text': 'Will this question show up on sepolia reality.eth?  #fe8880c...0229f78\n\n⇒Answer', '$type': 'app.bsky.feed.post', 'facets': [{'index': {'byteEnd': 81, 'byteStart': 71}, 'features': [{'uri': 'https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0xfe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78', '$type': 'app.bsky.richtext.facet#link'}]}, {'index': {'byteEnd': 70, 'byteStart': 52}, 'features': [{'tag': 'fe8880cf92120dd15c4ef6d8897a7852b308cfcfb0741bcd1839517bb0229f78', '$type': app.bsky.richtext.facet#tag'}]}], 'createdAt': '2024-12-19T21:08:48.000Z'}
        bytes memory cbor = bytes(
            hex"a46474657874785157696c6c2074686973207175657374696f6e2073686f77207570206f6e207365706f6c6961207265616c6974792e6574683f202023666538383830632e2e2e303232396637380a0ae28792416e73776572652474797065726170702e62736b792e666565642e706f73746666616365747382a265696e646578a26762797465456e64185169627974655374617274184768666561747572657381a26375726978e568747470733a2f2f7265616c6974792e6574682e6c696e6b2f6170702f23212f6e6574776f726b2f31313135353131312f636f6e74726163742f3078616633336463623665386335633464396464663537396635333033316235313464313934343963612f746f6b656e2f4554482f7175657374696f6e2f3078616633336463623665386335633464396464663537396635333033316235313464313934343963612d307866653838383063663932313230646431356334656636643838393761373835326233303863666366623037343162636431383339353137626230323239663738652474797065781c6170702e62736b792e72696368746578742e6661636574236c696e6ba265696e646578a26762797465456e64184669627974655374617274183468666561747572657381a263746167784066653838383063663932313230646431356334656636643838393761373835326233303863666366623037343162636431383339353137626230323239663738652474797065781b6170702e62736b792e72696368746578742e666163657423746167696372656174656441747818323032342d31322d31395432313a30383a34382e3030305a"
        );

        uint256 foundCursor;
        uint256 end;

        DagCborNavigator.DagCborSelector[] memory goodSelector = new DagCborNavigator.DagCborSelector[](5);
        // mapping > facets > any item > features > any item > uri
        goodSelector[0] = DagCborNavigator.createSelector("tag");
        goodSelector[1] = DagCborNavigator.createSelector();
        goodSelector[2] = DagCborNavigator.createSelector("features");
        goodSelector[3] = DagCborNavigator.createSelector();
        goodSelector[4] = DagCborNavigator.createSelector("facets");

        (foundCursor, end) = client.firstMatch(cbor, goodSelector, 0, 0);
        //assertTrue(foundCursor > 0, "Found the match");
        //bytes memory uri = bytes(cbor[foundCursor:end]);
        //console.log(string(uri));
        //(,uint256 cursor,) = client.parseCborHeader(cbor, foundCursor);
    }
}
