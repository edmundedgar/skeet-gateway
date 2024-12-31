// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ParserUtil} from "../src/parsers/ParserUtil.sol";

contract ParserUtilTest is Test {
    function testDecimalParsing() external pure {
        bytes memory message = bytes(
            hex"302e3031323320455448652474797065726170702e62736b792e666565642e706f7374656c616e67738162656e6666616365747380696372656174656441747818323032342d31322d31395430363a30373a32332e3131325a"
        );
        uint256 amount;
        uint256 cursor;
        (amount, cursor) = ParserUtil.stringStartingWithDecimalsToUint256(string(message), 18);
        // 0.0123 * 10^18 0012300000000000000
        assertEq(amount, 12300000000000000);
    }
}
