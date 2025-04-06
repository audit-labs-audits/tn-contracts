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
import { Create3Utils, Salts, ImplSalts } from "../deployments/utils/Create3Utils.sol";
import { Deployments, ITS } from "../deployments/Deployments.sol";
import { ITSConfig } from "../deployments/utils/ITSConfig.sol";
import { StorageDiffRecorder } from "../deployments/genesis/StorageDiffRecorder.sol";
import { ITSGenesis } from "../deployments/genesis/ITSGenesis.sol";

/// @title Interchain Token Service Genesis Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values
/// Used by Telcoin-Network protocol to instantiate the contracts with required configuration at genesis

/// @dev Usage: `forge script script/GenerateITSGenesisConfig.s.sol -vvvv`
contract GenerateITSGenesisConfig is ITSGenesis, Script {
    Deployments deployments;
    string root;
    string dest;

    function setUp() public {
        root = vm.projectRoot();
        dest = string.concat(root, "/deployments/genesis/its-config.yaml");
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        address admin = deployments.admin;
        rwtelOwner = admin;

        /// @dev For testnet and mainnet genesis configs, use corresponding function
        _setUpDevnetConfig(admin, deployments.sepoliaTEL, deployments.wTEL, deployments.rwTEL);

        _setGenesisTargets(deployments.its, payable(deployments.wTEL), payable(deployments.rwTELImpl), payable(deployments.rwTEL), deployments.rwTELTokenManager);

        // create3 contract only used for simulation; will not be instantiated at genesis
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
    }

    function run() public {
        vm.startBroadcast();

        // initialize yaml file
        vm.writeLine(dest, "---"); // indicate yaml format

        // wTEL
        address simulatedWTEL = address(payable(instantiateWTEL()));
        yamlAppendBytecode(dest, simulatedWTEL, deployments.wTEL);

        // rwTEL impl before ITS to fetch token id for TokenHandler::constructor
        address simulatedRWTELImpl = address(instantiateRWTELImpl(deployments.its.InterchainTokenService));
        yamlAppendBytecode(dest, simulatedRWTELImpl, deployments.rwTELImpl);
        canonicalInterchainTokenId = rwTELImpl.interchainTokenId();

        // gateway impl (no storage)
        address simulatedGatewayImpl = address(instantiateAxelarAmplifierGatewayImpl());
        yamlAppendBytecode(dest, simulatedGatewayImpl, deployments.its.AxelarAmplifierGatewayImpl);
        // gateway (has storage)
        address simulatedGateway =
            address(instantiateAxelarAmplifierGateway(deployments.its.AxelarAmplifierGatewayImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedGateway, deployments.its.AxelarAmplifierGateway);
        // token manager deployer (no storage)
        address simulatedTMD = address(instantiateTokenManagerDeployer());
        yamlAppendBytecode(dest, simulatedTMD, deployments.its.TokenManagerDeployer);
        // it impl (no storage)
        address simulatedITImpl = address(instantiateInterchainTokenImpl(deployments.its.InterchainTokenService));
        yamlAppendBytecode(dest, simulatedITImpl, deployments.its.InterchainTokenImpl);
        // itd (no storage)
        address simulatedITD = address(instantiateInterchainTokenDeployer(deployments.its.InterchainTokenImpl));
        yamlAppendBytecode(dest, simulatedITD, deployments.its.InterchainTokenDeployer);
        // tmImpl (no storage)
        address simulatedTMImpl = address(instantiateTokenManagerImpl(deployments.its.InterchainTokenService));
        yamlAppendBytecode(dest, simulatedTMImpl, deployments.its.TokenManagerImpl);
        // token handler (no storage)
        address simulatedTH = address(instantiateTokenHandler(canonicalInterchainTokenId));
        yamlAppendBytecode(dest, simulatedTH, deployments.its.TokenHandler);

        // gas service (has storage)
        vm.startStateDiffRecording();
        address simulatedGSImpl = address(instantiateAxelarGasServiceImpl());
        yamlAppendBytecode(dest, simulatedGSImpl, deployments.its.GasServiceImpl);
        address simulatedGS = address(instantiateAxelarGasService(deployments.its.GasServiceImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedGS, deployments.its.GasService);

        // gateway caller (no storage)
        address simulatedGC =
            address(instantiateGatewayCaller(deployments.its.AxelarAmplifierGateway, deployments.its.GasService));
        yamlAppendBytecode(dest, simulatedGC, deployments.its.GatewayCaller);

        // its (has storage)
        address simulatedITSImpl = address(
            instantiateITSImpl(
                deployments.its.TokenManagerDeployer,
                deployments.its.InterchainTokenDeployer,
                deployments.its.AxelarAmplifierGateway,
                deployments.its.GasService,
                deployments.its.InterchainTokenFactory,
                deployments.its.TokenManagerImpl,
                deployments.its.TokenHandler,
                deployments.its.GatewayCaller
            )
        );
        yamlAppendBytecode(dest, simulatedITSImpl, deployments.its.InterchainTokenServiceImpl);
        address simulatedITS = address(instantiateITS(deployments.its.InterchainTokenServiceImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedITS, deployments.its.InterchainTokenService);

        // itf (has storage)
        address simulatedITFImpl = address(instantiateITFImpl(deployments.its.InterchainTokenService));
        yamlAppendBytecode(dest, simulatedITFImpl, deployments.its.InterchainTokenFactoryImpl);
        address simulatedITF = address(instantiateITF(deployments.its.InterchainTokenFactoryImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedITF, deployments.its.InterchainTokenFactory);

        // rwtel (note: requires both storage and the total supply of TEL at genesis)
        address simulatedRWTEL = address(instantiateRWTEL(deployments.rwTELImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedRWTEL, deployments.rwTEL);

        vm.stopBroadcast();
    }
}
