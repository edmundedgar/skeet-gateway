// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ShadowDIDPLCDirectory} from "../src/ShadowDIDPLCDirectory.sol";

contract DeployShadowDidPLCDirectory is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ShadowDIDPLCDirectory();
        vm.stopBroadcast();
    }
}
