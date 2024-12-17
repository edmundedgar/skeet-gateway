// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";

contract SkeetGatewayScript is Script {
    SkeetGateway public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        counter = new SkeetGateway();

        vm.stopBroadcast();
    }
}
