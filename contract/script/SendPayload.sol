// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SkeetGateway} from "../src/SkeetGateway.sol";
import {BBS} from "../src/parsers/bbs/BBS.sol";
import {BBSMessageParser} from "../src/parsers/bbs/BBSMessageParser.sol";

contract SendPayload is Script {
    struct SkeetProof {
        string atURI;
        string botName;
        uint8 botNameLength;
        bytes commitNode;
        bytes[] content;
        string did;
        uint256[] nodeHints;
        bytes[] nodes;
        bytes32 r;
        string rkey;
        bytes32 s;
        uint8 v;
    }

    function run(address _gateway, string calldata _file) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        SkeetGateway gateway = SkeetGateway(_gateway);

        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/", _file));
        bytes memory data = vm.parseJson(json);
        SkeetProof memory proof = abi.decode(data, (SkeetProof));

        gateway.handleSkeet(
            proof.content,
            proof.botNameLength,
            proof.nodes,
            proof.nodeHints,
            proof.commitNode,
            proof.v,
            proof.r,
            proof.s
        );

        vm.stopBroadcast();
    }
}
