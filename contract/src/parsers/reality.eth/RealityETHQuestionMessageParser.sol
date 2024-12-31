// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMessageParser} from "../IMessageParser.sol";
import {IRealityETH} from "./IRealityETH.sol";

contract RealityETHQuestionMessageParser is IMessageParser {
    address realityETH;
    address arbitrator;

    constructor(address _realityETH, address _arbitrator) {
        realityETH = _realityETH;
        arbitrator = _arbitrator;
    }

    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        view
        returns (address, uint256 value, bytes memory)
    {
        bytes memory data = abi.encodeWithSignature(
            "askQuestion(uint256,string,address,uint32,uint32,uint256)",
            uint256(0),
            string(content[0][messageStart:messageEnd]),
            arbitrator,
            uint32(24 * 60 * 60 * 3), // 3 days
            uint32(block.timestamp),
            uint256(0)
        );
        return (realityETH, 0, data);
    }
}
