// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Test, console} from "forge-std/Test.sol";

abstract contract SkeetProofLoader is Test {
    struct SkeetProof {
        string atURI;
        string botName;
        uint8 botNameLength;
        bytes commitNode;
        bytes[] content;
        string did;
        uint256[] nodeHints;
        bytes[] nodes;
        string rkey;
        bytes sig;
    }

    function _loadProofFixture(string memory fixtureName) internal view returns (SkeetProof memory) {
        string memory fixture = string.concat("/test/fixtures/", fixtureName);
        string memory json = vm.readFile(string.concat(vm.projectRoot(), fixture));
        bytes memory data = vm.parseJson(json);
        SkeetProof memory proof = abi.decode(data, (SkeetProof));
        return proof;
    }
}
