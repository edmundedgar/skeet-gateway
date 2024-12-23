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

        // TODO sort this out to use the params
        bytes memory realityETHURLPrefix = hex"78e568747470733A2F2F7265616C6974792E6574682E6C696E6B2F6170702F23212F6E6574776F726B2F31313135353131312F636F6E74726163742F3078616633336463623665386335633464396464663537396635333033316235313464313934343963612F746F6B656E2F4554482F7175657374696F6E2F3078616633336463623665386335633464396464663537396635333033316235313464313934343963612D3078";
        RealityETHAnswerMessageParser answerParser = new RealityETHAnswerMessageParser(_realityETH, realityETHURLPrefix);
        gateway.addBot(_answerBot, _domain, address(answerParser));

        vm.stopBroadcast();
    }
}
