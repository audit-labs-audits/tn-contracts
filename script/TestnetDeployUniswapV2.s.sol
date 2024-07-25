// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";

contract TestnetDeployUniswapV2 is Script {

    function setUp() public {}
    function run() public {
        // deploy v2 core contracts
        // deploy UniswapV2ERC20
        // deploy UniswapV2Factory

        // deploy v2 periphery contracts
        // deploy UniswapV2Router02

        // create pools for existing tokens
        // weth, recoverable pools
        // stablecoin pools

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/log/deployments.json");
        vm.writeLine(dest, string.concat("wTEL: ", LibString.toHexString(uint256(uint160(address(wTEL))), 20)));
        vm.writeLine(dest, string.concat("rwTEL: ", LibString.toHexString(uint256(uint160(address(rwTEL))), 20)));
        vm.writeLine(
            dest,
            string.concat("StablecoinImpl: ", LibString.toHexString(uint256(uint160(address(stablecoinImpl))), 20))
        );
    }
}