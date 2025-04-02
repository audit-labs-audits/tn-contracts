// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { Create3AddressFixed } from "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { TokenManagerProxy } from "@axelar-network/interchain-token-service/contracts/proxies/TokenManagerProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { ITokenManager } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "../deployments/utils/Create3Utils.sol";
import { Deployments } from "../deployments/Deployments.sol";
import { ITSUtilsFork } from "../deployments/utils/ITSUtilsFork.sol";
import { StorageDiffRecorder } from "../deployments/utils/StorageDiffRecorder.sol";

/// @title Interchain Token Service Genesis Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values
/// Used by Telcoin-Network protocol to instantiate the contracts with required configuration at genesis

/// @dev Usage: `forge script script/GenerateITSGenesisConfig.s.sol -vvvv`
contract GenerateITSConfig is ITSUtilsFork, StorageDiffRecorder, Script {
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;
    address rwtelOwner;

    Create3Deployer create3; // not included in genesis

    Deployments deployments;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        wTEL = WTEL(payable(deployments.wTEL)); //todo: bring wTEL into genesis also
        address admin = deployments.admin;
        rwtelOwner = admin;
        
        /// @dev For testnet and mainnet genesis configs, use corresponding function
        _setUpDevnetConfig(
            admin,
            deployments.sepoliaTEL,
            deployments.wTEL,
            deployments.its.InterchainTokenService,
            deployments.its.InterchainTokenFactory
        );

        // create3 contract only used for simulation; will not be instantiated at genesis
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
    }

    function run() public {
        vm.startBroadcast();

        // initialize yaml file
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/deployments/its-config.yaml");
        vm.writeLine(dest, "---"); // indicate yaml format

        // gateway (has storage)
        vm.startStateDiffRecording();
        gatewayImpl = create3DeployAxelarAmplifierGatewayImpl(create3);
        vm.etch(deployments.its.AxelarAmplifierGatewayImpl, address(gatewayImpl).code); // prevent constructor revert
        gateway = create3DeployAxelarAmplifierGateway(create3, deployments.its.AxelarAmplifierGatewayImpl);
        Vm.AccountAccess[] memory gatewayRecords = vm.stopAndReturnStateDiff();
        // save impl bytecode since immutable variables are set in constructor
        yamlAppendBytecode(dest, address(gatewayImpl), deployments.its.AxelarAmplifierGatewayImpl);
        saveWrittenSlots(address(gateway), gatewayRecords);
        yamlAppendBytecodeWithStorage(dest, address(gateway), deployments.its.AxelarAmplifierGateway);

        // token manager deployer (no storage)
        tokenManagerDeployer = create3DeployTokenManagerDeployer(create3);
        yamlAppendBytecode(dest, address(tokenManagerDeployer), deployments.its.TokenManagerDeployer);
        // it impl (no storage)
        interchainTokenImpl = create3DeployInterchainTokenImpl(create3);
        yamlAppendBytecode(dest, address(interchainTokenImpl), deployments.its.InterchainTokenImpl);
        // itd (no storage)
        itDeployer = create3DeployInterchainTokenDeployer(create3, deployments.its.InterchainTokenImpl);
        yamlAppendBytecode(dest, address(itDeployer), deployments.its.InterchainTokenDeployer);
        // tmImpl (no storage)
        tokenManagerImpl = create3DeployTokenManagerImpl(create3);
        yamlAppendBytecode(dest, address(tokenManagerImpl), deployments.its.TokenManagerImpl);
        // token handler (no storage)
        tokenHandler = create3DeployTokenHandler(create3);
        yamlAppendBytecode(dest, address(tokenHandler), deployments.its.TokenHandler);

        // gas service (has storage)
        vm.startStateDiffRecording();
        gasServiceImpl = create3DeployAxelarGasServiceImpl(create3);
        vm.etch(deployments.its.GasServiceImpl, address(gasServiceImpl).code); // prevent constructor revert
        gasService = create3DeployAxelarGasService(create3, deployments.its.GasServiceImpl);
        Vm.AccountAccess[] memory gsRecords = vm.stopAndReturnStateDiff();
        yamlAppendBytecode(dest, address(gasServiceImpl), deployments.its.GasServiceImpl);
        saveWrittenSlots(address(gasService), gsRecords);
        yamlAppendBytecodeWithStorage(dest, address(gasService), deployments.its.GasService);

        // gateway caller (no storage)
        gatewayCaller =
            create3DeployGatewayCaller(create3, deployments.its.AxelarAmplifierGateway, deployments.its.GasService);
        yamlAppendBytecode(dest, address(gatewayCaller), deployments.its.GatewayCaller);

        // its (has storage)
        vm.startStateDiffRecording();
        itsImpl = create3DeployITSImpl(
            create3,
            deployments.its.TokenManagerDeployer,
            deployments.its.InterchainTokenDeployer,
            deployments.its.AxelarAmplifierGateway,
            deployments.its.GasService,
            deployments.its.TokenManagerImpl,
            deployments.its.TokenHandler,
            deployments.its.GatewayCaller
        );
        its = create3DeployITS(create3, deployments.its.InterchainTokenServiceImpl);
        Vm.AccountAccess[] memory itsRecords = vm.stopAndReturnStateDiff();
        yamlAppendBytecode(dest, address(itsImpl), deployments.its.InterchainTokenServiceImpl);
        saveWrittenSlots(address(its), itsRecords);
        yamlAppendBytecodeWithStorage(dest, address(its), deployments.its.InterchainTokenService);

        // itf (has storage)
        vm.etch(deployments.its.InterchainTokenService, address(itsImpl).code); // prevent constructor revert
        vm.startStateDiffRecording();
        itFactoryImpl = create3DeployITFImpl(create3, deployments.its.InterchainTokenService);
        itFactory = create3DeployITF(create3, deployments.its.InterchainTokenFactoryImpl);
        Vm.AccountAccess[] memory itfRecords = vm.stopAndReturnStateDiff();
        yamlAppendBytecode(dest, address(itFactoryImpl), deployments.its.InterchainTokenFactoryImpl);
        saveWrittenSlots(address(itFactory), itfRecords);
        yamlAppendBytecodeWithStorage(dest, address(itFactory), deployments.its.InterchainTokenFactory);

        // rwtel (note: requires both storage and the total supply of TEL at genesis)
        vm.startStateDiffRecording();
        rwTELImpl = create3DeployRWTELImpl(create3, deployments.its.InterchainTokenService);
        vm.etch(deployments.rwTELImpl, address(rwTELImpl).code); // prevent constructor revert
        rwTEL = create3DeployRWTEL(create3, deployments.rwTELImpl);
        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);
        Vm.AccountAccess[] memory rwtelRecords = vm.stopAndReturnStateDiff();
        yamlAppendBytecode(dest, address(rwTELImpl), deployments.rwTELImpl);
        saveWrittenSlots(address(rwTEL), rwtelRecords);
        yamlAppendBytecodeWithStorage(dest, address(rwTEL), deployments.rwTEL);

        vm.stopBroadcast();
    }
}
