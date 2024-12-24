// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {RealityETHQuestionMessageParser} from "src/parsers/reality.eth/RealityETHQuestionMessageParser.sol";
import {RealityETHAnswerMessageParser} from "src/parsers/reality.eth/RealityETHAnswerMessageParser.sol";

// Create parsers for reality.eth actions and register it with the gateway
contract AddBotRealityETHBots is Script {
    function run(
        address _gateway,
        address _realityETH,
        address _arbitrator,
        string calldata _realityETHURLPrefix,
        string calldata _domain,
        string calldata _questionBot,
        string calldata _answerBot
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address owner = vm.addr(deployerPrivateKey);

        SkeetGateway gateway = SkeetGateway(_gateway);
        gateway.addDomain(_domain, owner);

        RealityETHQuestionMessageParser questionParser = new RealityETHQuestionMessageParser(_realityETH, _arbitrator);
        gateway.addBot(_questionBot, _domain, address(questionParser));

        RealityETHAnswerMessageParser answerParser =
            new RealityETHAnswerMessageParser(_realityETH, _realityETHURLPrefix);
        gateway.addBot(_answerBot, _domain, address(answerParser));

        vm.stopBroadcast();
    }
}
