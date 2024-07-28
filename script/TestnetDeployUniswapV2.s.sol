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
    address wTEL;
    address feeToSetter_;
    address admin;
    bytes32 factorySalt;
    bytes32 routerSalt;

    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router02;
    // todo convert to array
    IUniswapV2Pair wTELeAUD;
    IUniswapV2Pair wTELeCAD;
    IUniswapV2Pair wTELeCHF;
    IUniswapV2Pair wTELeEUR;
    IUniswapV2Pair wTELeGBP;
    IUniswapV2Pair wTELeHKD;
    IUniswapV2Pair wTELeJPY;
    IUniswapV2Pair wTELeMXN;
    IUniswapV2Pair wTELeNOK;
    IUniswapV2Pair wTELeSDR;
    IUniswapV2Pair wTELeSGD;

    Deployments deployments;

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
    }

    function run() public {
        // deploy v2 core contracts
        bytes memory factoryInitcode = bytes.concat(UNISWAPV2FACTORY_BYTECODE, abi.encode(feeToSetter_));
        uniswapV2Factory = IUniswapV2Factory(CREATE3.deployDeterministic(factoryInitcode, factorySalt));

        // deploy v2 periphery contracts
        bytes memory router02Initcode = bytes.concat(UNISWAPV2ROUTER02_BYTECODE, bytes32(uint256(uint160(address(uniswapV2Factory)))), bytes32(uint256(uint160(wTEL))));
        uniswapV2Router02 = IUniswapV2Router02(CREATE3.deployDeterministic(router02Initcode, routerSalt));

        // configure pairs
        wTELeAUD = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eAUD));
        wTELeCAD = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eCAD));
        wTELeCHF = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eCHF));
        wTELeEUR = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eEUR));
        wTELeGBP = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eGBP));
        wTELeHKD = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eHKD));
        wTELeJPY = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eJPY));
        wTELeMXN = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eMXN));
        wTELeNOK = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eNOK));
        wTELeSDR = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eSDR));
        wTELeSGD = IUniswapV2Pair(uniswapV2Factory.createPair(wTEL, deployments.eSGD));

        // asserts
        assert(address(uniswapV2Factory).code.length != 0);
        assert(uniswapV2Factory.feeToSetter() == admin);
        assert(address(uniswapV2Router02).code.length != 0);
        assert(uniswapV2Router02.factory() == address(uniswapV2Factory));
        assert(uniswapV2Router02.WETH() == wTEL);

        assert(wTELeAUD.factory() == address(uniswapV2Factory));
        assert(wTELeAUD.token0() == deployments.eAUD);
        assert(wTELeAUD.token1() == wTEL);
        assert(wTELeCAD.factory() == address(uniswapV2Factory));
        assert(wTELeCAD.token0() == deployments.eCAD);
        assert(wTELeCAD.token1() == wTEL);
        assert(wTELeCHF.factory() == address(uniswapV2Factory));
        assert(wTELeCHF.token0() == wTEL);
        assert(wTELeCHF.token1() == deployments.eCHF);
        //etc (convert to array)

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/log/deployments.json");
        // todo: convert to writeJson
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
