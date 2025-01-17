// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BokkyPooBahsDateTimeLibrary} from "@bokkypoobah/BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";

import {console} from "forge-std/console.sol";

library TimeFormat {

    using BokkyPooBahsDateTimeLibrary for uint256;

    function _utf8ToUint256(bytes memory utf8num) internal pure returns (uint256) {
        uint256 numBytes = utf8num.length;
        uint256 result = 0;
        for (uint256 i = 0; i < numBytes; i++) {
console.logBytes1(utf8num[i]);
            uint8 c = uint8(bytes1(utf8num[i]));
            if (c < 48 || c > 57) {
                revert("not a digit");
            }
            result = result * 10 + (c - 48);
        }
console.log("return");
console.log(result);
        return result;
    }
    
    // In actual data we see 2025-01-16T05:55:09.258Z
    // We will also support 20250116T062215Z
    // We won't check anything beyond the ".", I hope you're using UTC
    function timestampFromISO8601DatetimeUTC(bytes calldata dt) internal pure returns (uint256) {

        console.log(string(dt));
        uint256 year;
        uint256 month;
        uint256 day;
        uint256 hour;
        uint256 minute;
        uint256 second;

        year = _utf8ToUint256(dt[0:4]);
        console.logBytes(dt[0:4]);
        require(year > 1969 && year < 3000, "year outside expected range");

        if (bytes1(dt[4:5]) == bytes1(hex"2d")) {

            month = _utf8ToUint256(dt[5:7]);
            require(bytes1(dt[7:8]) == bytes1(hex"2d"), "month-day needs - delim");
            day = _utf8ToUint256(dt[8:10]);
            require(bytes1(dt[10:11]) == bytes1(hex"54"), "date-time needs T delim");
            hour = _utf8ToUint256(dt[11:13]);
            require(bytes1(dt[13:14]) == bytes1(hex"3a"), "hour:min needs : delim");
            minute = _utf8ToUint256(dt[14:16]);
            require(bytes1(dt[16:17]) == bytes1(hex"3a"), "min:sec needs : delim");
            second = _utf8ToUint256(dt[17:19]);

        } else {
            month = _utf8ToUint256(dt[4:6]);
            day = _utf8ToUint256(dt[6:8]);
            require(bytes1(dt[8:9]) == bytes1(hex"54"), "date-time needs T delim");
            hour = _utf8ToUint256(dt[9:11]);
            minute = _utf8ToUint256(dt[11:13]);
            second = _utf8ToUint256(dt[13:15]);
        }

        require(month > 0 && month < 13, "bad month");
        require(day > 0 && day < 32, "bad day");
        require(hour >= 0 && hour < 25, "bad hour");
        require(minute >= 0 && minute < 61, "bad minute");
        require(second >= 0 && second < 61, "bad second");
        return BokkyPooBahsDateTimeLibrary.timestampFromDateTime(year, month, day, hour, minute, second);
    }

}
