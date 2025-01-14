// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DidProofLoader} from "./DidProofLoader.sol";
import {Vm} from "forge-std/Vm.sol";
import {DidVerifier} from "../src/DidVerifier.sol";
import {console} from "forge-std/console.sol";

contract DidVerifierTest is Test, DidProofLoader {
    DidVerifier public didVerifier;
}
