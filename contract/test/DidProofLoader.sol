// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Test, console} from "forge-std/Test.sol";

abstract contract DidProofLoader is Test {
    struct DidProof {
        string did;
        bytes[] ops;
        uint256[] pubkeyIndexes;
        bytes[] pubkeys;
        bytes[] sigs;
    }

    function _loadProofFixture(string memory fixtureName) internal view returns (DidProof memory) {
        string memory fixture = string.concat("/test/fixtures/did/", fixtureName);
        string memory json = vm.readFile(string.concat(vm.projectRoot(), fixture));
        bytes memory data = vm.parseJson(json);
        DidProof memory proof = abi.decode(data, (DidProof));
        return proof;
    }
}
