// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
import { IUniswapV2Factory } from "script/uniswap/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "script/uniswap/interfaces/IUniswapV2Router02.sol";
import { UniswapV2FactoryBytecode } from "script/uniswap/precompiles/UniswapV2FactoryBytecode.sol";
import { UniswapV2Router02Bytecode } from "script/uniswap/precompiles/UniswapV2Router02Bytecode.sol";
import { WTEL } from "../src/WTEL.sol";

contract TestnetDeployUniswapV2 is Script, UniswapV2FactoryBytecode, UniswapV2Router02Bytecode {

    address wTEL;
    address feeToSetter_;
    address admin;
    bytes32 factorySalt;
    bytes32 routerSalt;

    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router02;

    function setUp() public {
        // todo: read JSON for these
        wTEL = 0x5c78ebbcfdc8Fd432C6D7581F6F8E6B82079f24a;
        admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
        feeToSetter_ = admin;

        factorySalt = bytes32(bytes("UniswapV2Factory"));
        routerSalt = bytes32(bytes("UniswapV2Router02"));
    }

    function run() public {
        // deploy v2 core contracts
        //todo constructor: feeToSetter
        uniswapV2Factory = IUniswapV2Factory(CREATE3.deployDeterministic(UNISWAPV2FACTORY_BYTECODE, factorySalt));

        // deploy v2 periphery contracts
        //todo constructor: (address(uniswapV2Factory), wTEL)
        uniswapV2Router02 = IUniswapV2Router02(CREATE3.deployDeterministic(UNISWAPV2ROUTER02_BYTECODE, routerSalt));

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
}
