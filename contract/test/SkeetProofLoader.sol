// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from "forge-std/Vm.sol";
import {Test, console} from "forge-std/Test.sol";

abstract contract SkeetProofLoader is Test {

    struct SkeetProof {
        uint8 botNameLength;
        bytes commitNode;
        bytes[] content;
        string did;
        uint256[] nodeHints;
        bytes[] nodes;
        bytes32 r;
        string rkey;
        bytes32 s;
    }

    function _loadProofFixture(string memory fixtureName) internal view returns (SkeetProof memory) {
        string memory fixture = string.concat("/test/fixtures/", fixtureName);
        string memory json = vm.readFile(string.concat(vm.projectRoot(), fixture));
        bytes memory data = vm.parseJson(json);
        SkeetProof memory proof = abi.decode(data, (SkeetProof));
        return proof;
    }

}
