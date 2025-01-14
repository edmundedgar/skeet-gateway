// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMessageParser} from "../IMessageParser.sol";
import {ParserUtil} from "../ParserUtil.sol";

import {Safe} from "../../../lib/safe-contracts/contracts/Safe.sol";

contract SafeAddOwnerMessageParser is IMessageParser {
    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd, address signerSafe)
        external
        view
        returns (address, uint256 value, bytes memory)
    {
        require(messageEnd - messageStart == 42, "Message should be 0x then 40 chars (20 bytes)");
        address addAddress = ParserUtil.stringToAddress(string(content[0][messageStart:messageEnd]));
        uint256 threshold = Safe(payable(signerSafe)).getThreshold();
        bytes memory data = abi.encodeWithSignature("addOwnerWithThreshold(address,uint256)", addAddress, threshold);
        return (signerSafe, 0, data);
    }
}
