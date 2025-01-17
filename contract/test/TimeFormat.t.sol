// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TimeFormat} from "../src/TimeFormat.sol";

contract TimeFormatClient {

    function callTimestampFromISO8601DatetimeUTC(bytes calldata dt) public pure returns (uint256) {
        return TimeFormat.timestampFromISO8601DatetimeUTC(dt);
    }

}

contract TimeFormatTest is Test {

    function testExpectedFormat() external {
        TimeFormatClient timeFormatClient = new TimeFormatClient();
        uint256 ts = timeFormatClient.callTimestampFromISO8601DatetimeUTC(bytes("2025-01-16T05:55:09.258Z"));
        assertEq(ts, 1737006909, "wrong time"); 
    }

    function testLegalAlternativeFormat() external {
        TimeFormatClient timeFormatClient = new TimeFormatClient();
        uint256 ts = timeFormatClient.callTimestampFromISO8601DatetimeUTC(bytes("20250116T055509Z"));
        assertEq(ts, 1737006909, "wrong time"); 
    }

    function testBadCharacter() external {
        TimeFormatClient timeFormatClient = new TimeFormatClient();
        vm.expectRevert();
        timeFormatClient.callTimestampFromISO8601DatetimeUTC(bytes("2025-a1-16T05:55:09.258Z"));
    }

    function testBadDateRange() external {
        TimeFormatClient timeFormatClient = new TimeFormatClient();
        vm.expectRevert();
        timeFormatClient.callTimestampFromISO8601DatetimeUTC(bytes("2025-14-16T05:55:09.258Z"));
    }

}
