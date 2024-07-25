// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { Stablecoin } from "telcoin-contracts/contracts/stablecoin/Stablecoin.sol";
import { WTEL } from "../src/WTEL.sol";

contract TestnetDeployTokens is Script {
    WTEL wTEL;
    RecoverableWrapper rwTEL;

    Stablecoin stablecoinImpl;
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

    //  admin, support, minter, burner role
    address admin;

    // shared Stablecoin creation params
    uint256 numStables;
    uint8 decimals_;
    uint256 maxLimit;
    uint256 minLimit;

    // specific Stablecoin creation params
    TokenMetadata[] metadatas;
    bytes32[] salts;
    bytes[] initDatas; // encoded Stablecoin.initialize() calls using metadatas

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

        numStables = 11;
        decimals_ = 6;

        // populate metadatas
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

        // populate deployDatas
        for (uint256 i; i < numStables; ++i) {
            TokenMetadata storage metadata = metadatas[i];
            bytes32 salt = bytes32(bytes(metadata.symbol));
            salts.push(salt);
            
            bytes memory initCall = abi.encodeWithSelector(Stablecoin.initialize.selector, metadata.name, metadata.symbol, decimals_);
            initDatas.push(initCall);
        }
    }

    function run() public {
        wTEL = new WTEL();
        rwTEL = new RecoverableWrapper(name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean);

        // deploy stablecoin impl and proxies
        stablecoinImpl = new Stablecoin();
        address[] memory deployedTokens = new address[](numStables);
        for (uint256 i; i < numStables; ++i) {
            address stablecoin = address(new ERC1967Proxy(address(stablecoinImpl), initDatas[i]));
            
            // grant deployer minter, burner & support roles
            bytes32 minterRole = Stablecoin(stablecoin).MINTER_ROLE();
            bytes32 burnerRole = Stablecoin(stablecoin).BURNER_ROLE();
            bytes32 supportRole = Stablecoin(stablecoin).SUPPORT_ROLE();
            Stablecoin(stablecoin).grantRole(minterRole, admin);
            Stablecoin(stablecoin).grantRole(burnerRole, admin);
            Stablecoin(stablecoin).grantRole(supportRole, admin);

            // push to array for asserts
            deployedTokens[i] = stablecoin;
        }

        // asserts
        for (uint256 i; i < numStables; ++i) {
            TokenMetadata memory tokenMetadata = metadatas[i];

            Stablecoin token = Stablecoin(deployedTokens[i]);
            assert(keccak256(bytes(token.name())) == keccak256(bytes(tokenMetadata.name)));
            assert(keccak256(bytes(token.symbol())) == keccak256(bytes(tokenMetadata.symbol)));
            assert(token.decimals() == decimals_);
        }

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/log/deployments.json");
        vm.writeLine(dest, string.concat("wTEL: ", LibString.toHexString(uint256(uint160(address(wTEL))), 20)));
        vm.writeLine(dest, string.concat("rwTEL: ", LibString.toHexString(uint256(uint160(address(rwTEL))), 20)));
        vm.writeLine(dest, string.concat("StablecoinImpl: ", LibString.toHexString(uint256(uint160(address(stablecoinImpl))), 20)));
        for (uint256 i; i < numStables; ++i) {
            vm.writeLine(dest, string.concat(Stablecoin(deployedTokens[i]).symbol(), ": ", LibString.toHexString(uint256(uint160(deployedTokens[i])), 20)));
        }
    }
}
