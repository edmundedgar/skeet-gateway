// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";

contract AddDomain is Script {
    function run(address _gateway, address _owner, string calldata _domain) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        SkeetGateway gateway = SkeetGateway(_gateway);

        gateway.addDomain(_domain, _owner);

        vm.stopBroadcast();
    }
}
