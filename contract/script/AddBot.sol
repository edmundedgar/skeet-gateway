// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";

contract AddBot is Script {
    function run(address _gateway, address _parser, string calldata _domain, string calldata _bot, string calldata _metadata) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        SkeetGateway gateway = SkeetGateway(_gateway);

        gateway.addBot(_bot, _domain, _parser, _metadata);

        vm.stopBroadcast();
    }
}
