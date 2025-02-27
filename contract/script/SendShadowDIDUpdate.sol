// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DidProofLoader} from "../test/DidProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {ShadowDIDPLCDirectory} from "../src/ShadowDIDPLCDirectory.sol";

contract SendShadowDIDUpdate is Script, DidProofLoader {
    function run(address _directory, string calldata _file) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ShadowDIDPLCDirectory directory = ShadowDIDPLCDirectory(_directory);
        DidProof memory proof = _loadDidProofFixture(_file);

        directory.registerUpdates(bytes32(0), proof.ops, proof.sigs, proof.pubkeys, proof.pubkeyIndexes);

        vm.stopBroadcast();
    }
}
