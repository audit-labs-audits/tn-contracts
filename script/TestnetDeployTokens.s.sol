// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { Stablecoin } from "telcoin-contracts/contracts/stablecoin/Stablecoin.sol";
import { StablecoinHandler } from "telcoin-contracts/contracts/stablecoin/StablecoinHandler.sol";
import { ClonableBeaconProxy } from "telcoin-contracts/contracts/external/openzeppelin/ClonableBeaconProxy.sol";
import { ProxyFactory } from "telcoin-contracts/contracts/factories/ProxyFactory.sol";
import { AmirX } from "telcoin-contracts/contracts/swap/AmirX.sol";
import { WTEL } from "../src/WTEL.sol";

contract TestnetDeployTokens is Script {
    WTEL wTEL;
    RecoverableWrapper rwTEL;
    ProxyFactory proxyFactory;
    Stablecoin stablecoinImpl;
    UpgradeableBeacon stablecoinBeacon;
    ClonableBeaconProxy beaconProxy;
    StablecoinHandler stablecoinHandler;
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
    AmirX amirX;

    // rwTEL constructor params
    string name_;
    string symbol_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;

    // factory admin, stablecoin support+maintainer role
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
        admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;

        name_ = "Recoverable Wrapped Telcoin";
        symbol_ = "rwTEL";
        recoverableWindow_ = 86_400; // ~1 day; Telcoin Network blocktime is ~1s
        governanceAddress_ = admin; // multisig/council/DAO address in prod
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
            TokenMetadata storage metadata = metadatas[i];
            bytes32 salt = bytes32(bytes(metadata.symbol));
            salts_.push(salt);

            // bytes memory initCall = abi.encodeWithSelector(ClonableBeaconProxy.initialize.selector, address());
            initDatas_.push('');
        }
    }

    function run() public {
        wTEL = new WTEL();
        rwTEL = new RecoverableWrapper(name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean);

        // deploy beacon impl and proxy
        stablecoinImpl = new Stablecoin();
        stablecoinBeacon =  new UpgradeableBeacon(address(stablecoinImpl), admin);

        // beaconProxy = new ClonableBeaconProxy();
        // beaconProxy.initialize(address(stablecoinImpl), '');

        // deploy beacon factory
        proxyFactory = new ProxyFactory();
        proxyFactory.initialize(admin, address(stablecoinImpl), address(beaconProxy));

        // todo
        // amirXImpl = new AmirX();
        // amirX = new proxy

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/log/deployment.json");
        vm.writeFile(dest, string.concat("wTEL: ", LibString.toHexString(uint256(uint160(address(wTEL))), 20)));
        vm.writeFile(dest, string.concat("rwTEL: ", LibString.toHexString(uint256(uint160(address(rwTEL))), 20)));
        vm.writeFile(dest, string.concat("ProxyFactory: ", LibString.toHexString(uint256(uint160(address(proxyFactory))), 20)));
        vm.writeFile(dest, string.concat("StablecoinImpl: ", LibString.toHexString(uint256(uint160(address(stablecoinImpl))), 20)));
        vm.writeFile(dest, string.concat("eAUD: ", LibString.toHexString(uint256(uint160(address(eAUD))), 20)));
        vm.writeFile(dest, string.concat("eCAD: ", LibString.toHexString(uint256(uint160(address(eCAD))), 20)));
        vm.writeFile(dest, string.concat("eCHF: ", LibString.toHexString(uint256(uint160(address(eCHF))), 20)));
        vm.writeFile(dest, string.concat("eEUR: ", LibString.toHexString(uint256(uint160(address(eEUR))), 20)));
        vm.writeFile(dest, string.concat("eGBP: ", LibString.toHexString(uint256(uint160(address(eGBP))), 20)));
        vm.writeFile(dest, string.concat("eHKD: ", LibString.toHexString(uint256(uint160(address(eHKD))), 20)));
        vm.writeFile(dest, string.concat("eMXN: ", LibString.toHexString(uint256(uint160(address(eMXN))), 20)));
        vm.writeFile(dest, string.concat("eNOK: ", LibString.toHexString(uint256(uint160(address(eNOK))), 20)));
        vm.writeFile(dest, string.concat("eJPY: ", LibString.toHexString(uint256(uint160(address(eJPY))), 20)));
        vm.writeFile(dest, string.concat("eSDR: ", LibString.toHexString(uint256(uint160(address(eSDR))), 20)));
        vm.writeFile(dest, string.concat("eSGD: ", LibString.toHexString(uint256(uint160(address(eSGD))), 20)));
    }
}
