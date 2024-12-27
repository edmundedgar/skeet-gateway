// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";

import {BBS} from "../src/parsers/bbs/BBS.sol";
import {BBSMessageParser} from "../src/parsers/bbs/BBSMessageParser.sol";

import {RealityETHAnswerMessageParser} from "src/parsers/reality.eth/RealityETHAnswerMessageParser.sol";
import {RealityETHQuestionMessageParser} from "src/parsers/reality.eth/RealityETHQuestionMessageParser.sol";

import {PayMessageParser} from "../src/parsers/pay/PayMessageParser.sol";

contract DeployEverything is Script {
    // Struct to match the config file input/deploy_parameters.json
    struct DeployParameters {
        string bbsBot;
        string bbsDomain;
        string[] domains;
        string payBot;
        string payDomain;
        address realityETH;
        string realityETHAnswerBot;
        string realityETHAnswerDomain;
        address realityETHArbitrator;
        string realityETHQuestionBot;
        string realityETHQuestionDomain;
        string realityETHURLPrefix;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/script/input/deploy_parameters.json"));
        bytes memory data = vm.parseJson(json);
        DeployParameters memory params = abi.decode(data, (DeployParameters));

        SkeetGateway gateway = new SkeetGateway();
        for (uint256 i = 0; i < params.domains.length; i++) {
            gateway.addDomain(params.domains[i], address(tx.origin));
        }

        BBS bbs = new BBS();
        BBSMessageParser bbsParser = new BBSMessageParser(address(bbs));
        gateway.addBot(params.bbsBot, params.bbsDomain, address(bbsParser), "");

        PayMessageParser payParser = new PayMessageParser();
        gateway.addBot(params.payBot, params.payDomain, address(payParser), "");

        RealityETHQuestionMessageParser questionParser =
            new RealityETHQuestionMessageParser(params.realityETH, params.realityETHArbitrator);
        gateway.addBot(params.realityETHQuestionBot, params.realityETHQuestionDomain, address(questionParser), "");

        RealityETHAnswerMessageParser answerParser =
            new RealityETHAnswerMessageParser(params.realityETH, params.realityETHURLPrefix);
        gateway.addBot(params.realityETHAnswerBot, params.realityETHAnswerDomain, address(answerParser), '{"reply": 1}');

        vm.stopBroadcast();
    }
}
