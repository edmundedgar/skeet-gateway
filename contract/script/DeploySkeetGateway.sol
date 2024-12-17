// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {BBS} from "../src/BBS.sol";
import {BBSMessageParser} from "../src/BBSMessageParser.sol";

contract DeploySkeetGateway is Script {
    function setUp() public {}

    function run(string calldata _domain, string calldata _bot) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        SkeetGateway gateway = new SkeetGateway();

        BBS bbs = new BBS();
        BBSMessageParser bbsParser = new BBSMessageParser(address(bbs));

        // Set up with an initial domain and bot
        // You can add more later from the account you deployed this with
        gateway.addDomain(_domain, address(tx.origin));
        gateway.addBot(_bot, _domain, address(bbsParser));

        vm.stopBroadcast();
    }
}