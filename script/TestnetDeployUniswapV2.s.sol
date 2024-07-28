// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
import { IUniswapV2Factory } from "script/uniswap/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "script/uniswap/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "script/uniswap/interfaces/IUniswapV2Pair.sol";
import { UniswapV2FactoryBytecode } from "script/uniswap/precompiles/UniswapV2FactoryBytecode.sol";
import { UniswapV2Router02Bytecode } from "script/uniswap/precompiles/UniswapV2Router02Bytecode.sol";
import { WTEL } from "../src/WTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";

contract TestnetDeployUniswapV2 is Script, UniswapV2FactoryBytecode, UniswapV2Router02Bytecode {
    
    // deploys the following:
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router02;
    IUniswapV2Pair[] pairs; // 11 wTEL - stable pools

    // config
    Deployments deployments;
    address wTEL;
    address feeToSetter_;
    address admin;
    bytes32 factorySalt;
    bytes32 routerSalt;
    address[] stables;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        wTEL = deployments.wTEL; // 0x5c78ebbcfdc8Fd432C6D7581F6F8E6B82079f24a;
        admin = deployments.admin; // 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
        feeToSetter_ = admin;
        factorySalt = bytes32(bytes("UniswapV2Factory"));
        routerSalt = bytes32(bytes("UniswapV2Router02"));

        stables.push(deployments.eAUD);
        stables.push(deployments.eCAD);
        stables.push(deployments.eCHF);
        stables.push(deployments.eEUR);
        stables.push(deployments.eGBP);
        stables.push(deployments.eHKD);
        stables.push(deployments.eJPY);
        stables.push(deployments.eMXN);
        stables.push(deployments.eNOK);
        stables.push(deployments.eSDR);
        stables.push(deployments.eSGD);
    }

    function run() public {
        // deploy v2 core contracts
        bytes memory factoryInitcode = bytes.concat(UNISWAPV2FACTORY_BYTECODE, abi.encode(feeToSetter_));
        uniswapV2Factory = IUniswapV2Factory(CREATE3.deployDeterministic(factoryInitcode, factorySalt));

        // deploy v2 periphery contracts
        bytes memory router02Initcode = bytes.concat(
            UNISWAPV2ROUTER02_BYTECODE,
            bytes32(uint256(uint160(address(uniswapV2Factory)))),
            bytes32(uint256(uint160(wTEL)))
        );
        uniswapV2Router02 = IUniswapV2Router02(CREATE3.deployDeterministic(router02Initcode, routerSalt));

        // deploy v2 pools and record pair
        for (uint256 i; i < stables.length; ++i) {
            IUniswapV2Pair currentPair = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, stables[i]));
            pairs.push(currentPair);
        }

        // asserts
        assert(address(uniswapV2Factory).code.length != 0);
        assert(uniswapV2Factory.feeToSetter() == admin);
        assert(address(uniswapV2Router02).code.length != 0);
        assert(uniswapV2Router02.factory() == address(uniswapV2Factory));
        assert(uniswapV2Router02.WETH() == wTEL);

        for (uint256 i; i < pairs.length; ++i) {
            IUniswapV2Pair currentPair = pairs[i];
            bool correctFactory = currentPair.factory() == address(uniswapV2Factory);
            assert(correctFactory);

            address token0 = currentPair.token0();
            address token1 = currentPair.token1();
            bool correctToken0 = token0 == stables[i] || token0 == wTEL;
            bool correctToken1 = token1 == stables[i] || token1 == wTEL;
            assert(correctToken0);
            assert(correctToken1);
        }

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/deployments/deployments.json");
        vm.writeJson(LibString.toHexString(uint256(uint160(address(uniswapV2Factory))), 20), dest, ".UniswapV2Factory");
        vm.writeJson(LibString.toHexString(uint256(uint160(address(uniswapV2Router02))), 20), dest, ".UniswapV2Router02");
    }
}
