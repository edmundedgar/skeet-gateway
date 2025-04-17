// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMessageParser} from "../IMessageParser.sol";
import {ParserUtil} from "../ParserUtil.sol";

contract SafeCreateMessageParser is IMessageParser {
    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd, address)
        external
        view
        returns (address, uint256 value, bytes memory)
    {
        require(bytes3(content[0][messageStart:messageEnd]) == bytes3(bytes("new")), "Create message arg must be new");
        bytes memory data = abi.encodeWithSignature("createSafe()");
        return (msg.sender, 0, data);
    }
}
