// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMessageParser} from "../IMessageParser.sol";
import {BBS} from "./BBS.sol";

contract BBSMessageParser is IMessageParser {
    address bbs;

    constructor(address _bbs) {
        bbs = _bbs;
    }

    // TODO: If it doesn't cost too much maybe pass the whole message cbor as a parameter
    // This will allow the parser to check other things like replies
    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd)
        external
        returns (address, uint256 value, bytes memory)
    {
        bytes memory data = abi.encodeWithSignature("postMessage(string)", content[0][messageStart:messageEnd]);
        return (bbs, 0, data);
    }
}
