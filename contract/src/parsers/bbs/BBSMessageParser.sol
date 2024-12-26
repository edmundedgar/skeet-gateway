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
    function parseMessage(bytes calldata message) external view returns (address, uint256 value, bytes memory) {
        bytes memory data = abi.encodeWithSignature("postMessage(string)", message);
        return (bbs, 0, data);
    }
}
