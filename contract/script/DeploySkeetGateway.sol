// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {BBS} from "../src/parsers/bbs/BBS.sol";
import {BBSMessageParser} from "../src/parsers/bbs/BBSMessageParser.sol";

contract DeploySkeetGateway is Script {
    function setUp() public {}

    function run(string calldata _domain, string calldata _bot) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[] memory trustedObservers;
        SkeetGateway gateway = new SkeetGateway(address(0x41675C099F32341bf84BFc5382aF534df5C7461a), address(0), 0, trustedObservers);

        BBS bbs = new BBS();
        BBSMessageParser bbsParser = new BBSMessageParser(address(bbs));

        // Set up with an initial domain and bot
        // You can add more later from the account you deployed this with
        gateway.addDomain(_domain, address(tx.origin));
        gateway.addBot(_bot, _domain, address(bbsParser), "");

        vm.stopBroadcast();
    }
}
