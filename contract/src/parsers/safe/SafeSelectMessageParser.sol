// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMessageParser} from "../IMessageParser.sol";
import {ParserUtil} from "../ParserUtil.sol";

import {Safe} from "../../../lib/safe-contracts/contracts/Safe.sol";

contract SafeSelectMessageParser is IMessageParser {
    function parseMessage(bytes[] calldata content, uint256 messageStart, uint256 messageEnd, address signerSafe)
        external
        view
        returns (address, uint256 value, bytes memory)
    {
        (uint256 selection, ) = ParserUtil.stringStartingWithDecimalsToUint256(string(content[0][messageStart:messageEnd]), 0);
        bytes memory data = abi.encodeWithSignature("select(uint256)", selection);
        return (address(0), 0, data);
    }
}
