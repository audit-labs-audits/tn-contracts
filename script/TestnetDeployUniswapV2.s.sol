// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IUniswapV2Factory } from "script/uniswap/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "script/uniswap/interfaces/IUniswapV2Router02.sol";
import { WTEL } from "../src/WTEL.sol";

contract TestnetDeployUniswapV2 is Script {
    address wTEL;
    address feeToSetter_;
    address admin;

    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router02;

    function setUp() public {
        // wTEL = ;
        // feeToSetter = address(0x0);
        admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
        feeToSetter_ = admin;
    }

    function run() public {
        // deploy v2 core contracts
        feeToSetter_ = admin;
        // uniswapV2Factory = IUniswapV2Factory(vm.deployCode("script/uniswap/precompiles/UniswapV2Factory.json")); //
        // feeToSetter
        // deploy v2 periphery contracts
        // uniswapV2Router02 = IUniswapV2Router02(vm.deployCode("script/uniswap/precompiles/UniswapV2Router02.json"));
        // //address(uniswapV2Factory), wTEL

        // asserts
        assert(address(uniswapV2Factory).code.length != 0);
        assert(address(uniswapV2Router02).code.length != 0);

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/log/deployments.json");
        vm.writeLine(
            dest,
            string.concat("UniswapV2Factory: ", LibString.toHexString(uint256(uint160(address(uniswapV2Factory))), 20))
        );
        vm.writeLine(
            dest,
            string.concat(
                "UniswapV2Router02: ", LibString.toHexString(uint256(uint160(address(uniswapV2Router02))), 20)
            )
        );
    }

    // taken from https://ethereum.stackexchange.com/q/132029/86303
    function deployCode(bytes memory bytecode) internal returns (address payable addr) {
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))

            if iszero(extcodesize(addr)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}
