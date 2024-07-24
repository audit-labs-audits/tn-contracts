// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { LibString } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { Stablecoin } from "telcoin-contracts/contracts/stablecoin/Stablecoin.sol";
import { ProxyFactory } from "telcoin-contracts/contracts/factories/ProxyFactory.sol";
import { WTEL } from "../src/WTEL.sol";

contract TestnetDeploy is Script {

    WTEL wTEL;
    RecoverableWrapper rwTEL;
    ProxyFactory proxyFactory;
    ClonableBeaconProxy beaconProxy;
    Stablecoin implementation;
    Stablecoin eAUD; // 0x4392743b97c46c6aa186a7f3d0468fbf177ee70f
    Stablecoin eCAD; // 0xee7ca49702ce61d0a43214b45cf287efa046673a
    Stablecoin eCHF; // 0xabf991e50894174a492dce57e39c70a6344cc9a8
    Stablecoin eEUR; // 0x0739349c341319c193aebbd250819fbffd31f0bc
    Stablecoin eGBP; // 0xa5e5527d947a867ef3d22473c66ce335481545fb
    Stablecoin eHKD; // 0xfc42b8fa513dd03a13afac0908db61c7d50e9b40
    Stablecoin eMXN; // 0x89b3d9b5024f889cbca4cfc5fa262f198b967349
    Stablecoin eNOK; // 0x522d147139d249773e3e49b9b78e0c0c8a3d2ada
    Stablecoin eJPY; // 0xd38850877acd1180efb17e374bd00da2fdf024d2
    Stablecoin eSDR; // 0x5c32c13671e1805c851f6d4c7d76fd0bdfbfbe54 
    Stablecoin eSGD; // 0xb7be13b047e1151649191593c8f7719bb0563609

    // rwTEL constructor params
    string name_;
    string symbol_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;
    
    // factory admin
    address admin;

    // shared Stablecoin creation params
    uint256 numClones;
    uint8 decimals_;
    bytes32[] salts_; // bytes32(0...10)
    TokenMetadata[] metadatas;
    bytes[] initDatas_;

    struct TokenMetadata {
        string name;
        string symbol;
    }

    function setUp() public {
        name_ = "Recoverable Wrapped Telcoin";
        symbol_ = "rwTEL";
        recoverableWindow_ = 86_400; // ~1 day; Telcoin Network blocktime is ~1s
        governanceAddress_ = tester; // multisig/council/DAO address in prod
        baseERC20_ = address(wTEL);
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage

        numClones = 11;
        decimals_ = 6;
        metadatas.push(TokenMetadata("Telcoin AUD", "eAUD"));                
        metadatas.push(TokenMetadata("Telcoin CAD", "eCAD"));
        metadatas.push(TokenMetadata("Telcoin CHF", "eCHF"));
        metadatas.push(TokenMetadata("Telcoin EUR", "eEUR")); 
        metadatas.push(TokenMetadata("Telcoin GBP", "eGBP"));
        metadatas.push(TokenMetadata("Telcoin HKD", "eHKD"));
        metadatas.push(TokenMetadata("Telcoin MXN", "eMXN"));
        metadatas.push(TokenMetadata("Telcoin NOK", "eNOK"));
        metadatas.push(TokenMetadata("Telcoin JPY", "eJPY"));
        metadatas.push(TokenMetadata("Telcoin SDR", "eSDR"));
        metadatas.push(TokenMetadata("Telcoin SGD", "eSGD"));

        // populate salts, fetch metadatas and push abi-encoded initialization bytes to storage
        for (uint256 i; i < numClones; ++i) {
            salts_.push(i);

            TokenMetadata storage metadata = metadatas[i];
            bytes memory initCall = abi.encodeWithSelector(ClonableBeaconProxy.initialize.selector, address());
            initDatas_.push();
        }
    }

    function run() public {
        wTEL = new WTEL();
        rwTEL = new RecoverableWrapper(name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean);

        // deploy beacon implementation
        implementation = new Stablecoin();
        // deploy beacon factory
        proxyFactory = new ProxyFactory();
        proxyFactory.initialize(admin, address(implementation), address(beaconProxy));
        
        string root = vm.projectRoot();
        string dest = string.concat(root, "/log/deployment.json");
        vm.writeFile(dest, "wTEL: ", LibString.toString(address(wTEL)));
        vm.writeFile(dest, "rwTEL: ", LibString.toString(address(rwTEL)));
        vm.writeFile(dest, "ProxyFactory: ", LibString.toString(address(proxyFactory)));
        vm.writeFile(dest, "StablecoinImplementation: ", LibString.toString(address(implementation)));
        vm.writeFile(dest, "eAUD: ", LibString.toString(address(eAUD)));
        vm.writeFile(dest, "eCAD: ", LibString.toString(address(eCAD)));
        vm.writeFile(dest, "eCHF: ", LibString.toString(address(eCHF)));
        vm.writeFile(dest, "eEUR: ", LibString.toString(address(eEUR)));
        vm.writeFile(dest, "eGBP: ", LibString.toString(address(eGBP)));
        vm.writeFile(dest, "eHKD: ", LibString.toString(address(eHKD)));
        vm.writeFile(dest, "eMXN: ", LibString.toString(address(eMXN)));
        vm.writeFile(dest, "eNOK: ", LibString.toString(address(eNOK)));
        vm.writeFile(dest, "eJPY: ", LibString.toString(address(eJPY)));
        vm.writeFile(dest, "eSDR: ", LibString.toString(address(eSDR)));
        vm.writeFile(dest, "eSGD: ", LibString.toString(address(eSGD)));
    }
}
