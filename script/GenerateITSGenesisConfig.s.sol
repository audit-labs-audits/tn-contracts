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
import { ITSConfig } from "../deployments/utils/ITSConfig.sol";
import { StorageDiffRecorder } from "../deployments/utils/StorageDiffRecorder.sol";

/// @title Interchain Token Service Genesis Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values
/// Used by Telcoin-Network protocol to instantiate the contracts with required configuration at genesis

/// @dev Usage: `forge script script/GenerateITSGenesisConfig.s.sol -vvvv`
contract GenerateITSGenesisConfig is ITSConfig, StorageDiffRecorder, Script {

    Deployments deployments;
    string root;
    string dest;

    function setUp() public {
        root = vm.projectRoot();
        dest = string.concat(root, "/deployments/its-genesis-config.yaml");
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

        _setGenesisTargets(deployments.its, deployments.rwTELImpl, deployments.rwTEL);

        // create3 contract only used for simulation; will not be instantiated at genesis
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
    }

    function run() public {
        vm.startBroadcast();

        // initialize yaml file
        dest = string.concat(root, "/deployments/its-genesis-config.yaml");
        vm.writeLine(dest, "---"); // indicate yaml format

        // saving impl bytecodes since immutable variables are set in constructor
        // gateway impl (no storage)
        address simulatedGatewayImpl = address(instantiateAxelarAmplifierGatewayImpl());
        yamlAppendBytecode(dest, simulatedGatewayImpl, deployments.its.AxelarAmplifierGatewayImpl);
        // gateway (has storage)
        address simulatedGateway = address(instantiateAxelarAmplifierGateway(deployments.its.AxelarAmplifierGatewayImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedGateway, deployments.its.AxelarAmplifierGateway);
        // token manager deployer (no storage)
        address simulatedTMD = address(instantiateTokenManagerDeployer());
        yamlAppendBytecode(dest, simulatedTMD, deployments.its.TokenManagerDeployer);
        // it impl (no storage)
        address simulatedITImpl = address(instantiateInterchainTokenImpl());
        yamlAppendBytecode(dest, simulatedITImpl, deployments.its.InterchainTokenImpl);
        // itd (no storage)
        address simulatedITD = address(instantiateInterchainTokenDeployer(deployments.its.InterchainTokenImpl));
        yamlAppendBytecode(dest, simulatedITD, deployments.its.InterchainTokenDeployer);
        // tmImpl (no storage)
        address simulatedTMImpl = address(instantiateTokenManagerImpl());
        yamlAppendBytecode(dest, simulatedTMImpl, deployments.its.TokenManagerImpl);
        // token handler (no storage)
        address simulatedTH = address(instantiateTokenHandler());
        yamlAppendBytecode(dest, simulatedTH, deployments.its.TokenHandler);

        // gas service (has storage)
        vm.startStateDiffRecording();
        address simulatedGSImpl = address(instantiateAxelarGasServiceImpl());
        yamlAppendBytecode(dest, simulatedGSImpl, deployments.its.GasServiceImpl);
        address simulatedGS = address(instantiateAxelarGasService(deployments.its.GasServiceImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedGS, deployments.its.GasService);

        // gateway caller (no storage)
        address simulatedGC = address(instantiateGatewayCaller(deployments.its.AxelarAmplifierGateway, deployments.its.GasService));
        yamlAppendBytecode(dest, simulatedGC, deployments.its.GatewayCaller);

        // its (has storage)
        address simulatedITSImpl = address(instantiateITSImpl(
            deployments.its.TokenManagerDeployer,
            deployments.its.InterchainTokenDeployer,
            deployments.its.AxelarAmplifierGateway,
            deployments.its.GasService,
            deployments.its.TokenManagerImpl,
            deployments.its.TokenHandler,
            deployments.its.GatewayCaller
        ));
        yamlAppendBytecode(dest, simulatedITSImpl, deployments.its.InterchainTokenServiceImpl);
        address simulatedITS = address(instantiateITS(deployments.its.InterchainTokenServiceImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedITS, deployments.its.InterchainTokenService);

        // itf (has storage)
        address simulatedITFImpl = address(instantiateITFImpl(deployments.its.InterchainTokenService));
        yamlAppendBytecode(dest, simulatedITFImpl, deployments.its.InterchainTokenFactoryImpl);
        address simulatedITF = address(instantiateITF(deployments.its.InterchainTokenFactoryImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedITF, deployments.its.InterchainTokenFactory);

        // rwtel (note: requires both storage and the total supply of TEL at genesis)
        address simulatedRWTELImpl = address(instantiateRWTELImpl(deployments.its.InterchainTokenService));
        yamlAppendBytecode(dest, simulatedRWTELImpl, deployments.rwTELImpl);
        address simulatedRWTEL = address(instantiateRWTEL(deployments.rwTELImpl));
        yamlAppendBytecodeWithStorage(dest, simulatedRWTEL, deployments.rwTEL);

        vm.stopBroadcast();
    }

    /// @notice Genesis instantiation overrides of ITSUtils default implementations
    /// @dev Genesis target addresses for ITS suite & RWTEL must already be stored via `_setGenesisITS()`
    /// @dev All below genesis functions return the **simulated deployment**, copying state changes to storage targets

    function instantiateAxelarAmplifierGatewayImpl()
        public virtual override
        returns (AxelarAmplifierGateway simulatedDeployment)
    {
        simulatedDeployment = super.instantiateAxelarAmplifierGatewayImpl();
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(gatewayImpl), new bytes32[](0));
    }

    function instantiateAxelarAmplifierGateway(address impl)
        public virtual override
        returns (AxelarAmplifierGateway simulatedDeployment)
    {        
        vm.startStateDiffRecording();
        simulatedDeployment = super.instantiateAxelarAmplifierGateway(impl);
        Vm.AccountAccess[] memory gatewayRecords = vm.stopAndReturnStateDiff();

        // copy simulated state changes to target address in storage
        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), gatewayRecords);
        copyContractState(address(simulatedDeployment), address(gateway), slots);
    }

    function instantiateTokenManagerDeployer()
        public virtual override
        returns (TokenManagerDeployer simulatedDeployment)
    {
        simulatedDeployment = super.instantiateTokenManagerDeployer();
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(tokenManagerDeployer), new bytes32[](0));
    }

    function instantiateInterchainTokenImpl() public virtual override returns (InterchainToken simulatedDeployment) {
        simulatedDeployment = super.instantiateInterchainTokenImpl();
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(interchainTokenImpl), new bytes32[](0));
    }

    function instantiateInterchainTokenDeployer(
        address interchainTokenImpl_
    )
        public virtual override
        returns (InterchainTokenDeployer simulatedDeployment)
    {
        simulatedDeployment = super.instantiateInterchainTokenDeployer(interchainTokenImpl_);
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(itDeployer), new bytes32[](0));
    }

    function instantiateTokenManagerImpl() public virtual override returns (TokenManager simulatedDeployment) {
        simulatedDeployment = super.instantiateTokenManagerImpl();
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(tokenManagerImpl), new bytes32[](0));
    }

    function instantiateTokenHandler() public virtual override returns (TokenHandler simulatedDeployment) {
        simulatedDeployment = super.instantiateTokenHandler();
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(tokenHandler), new bytes32[](0));
    }

    function instantiateAxelarGasServiceImpl()
        public virtual override
        returns (AxelarGasService simulatedDeployment)
    {
        simulatedDeployment = super.instantiateAxelarGasServiceImpl();
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(gasServiceImpl), new bytes32[](0));
    }

    function instantiateAxelarGasService(address impl)
        public virtual override
        returns (AxelarGasService simulatedDeployment)
    {
        vm.startStateDiffRecording();
        simulatedDeployment = super.instantiateAxelarGasService(impl);
        Vm.AccountAccess[] memory gsRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), gsRecords);
        copyContractState(address(simulatedDeployment), address(gasService), slots);
    }

    function instantiateGatewayCaller( 
        address gateway_,
        address axelarGasService_
    )
        public virtual override
        returns (GatewayCaller simulatedDeployment)
    {
        simulatedDeployment = super.instantiateGatewayCaller(gateway_, axelarGasService_);
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(gatewayCaller), new bytes32[](0));
    }

    function instantiateITSImpl(
        address tokenManagerDeployer_,
        address itDeployer_,
        address gateway_,
        address gasService_,
        address tokenManagerImpl_,
        address tokenHandler_,
        address gatewayCaller_
    )
        public virtual override
        returns (InterchainTokenService simulatedDeployment)
    {
        simulatedDeployment = super.instantiateITSImpl(
            tokenManagerDeployer_,
            itDeployer_,
            gateway_,
            gasService_,
            tokenManagerImpl_,
            tokenHandler_,
            gatewayCaller_
        );
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(itsImpl), new bytes32[](0));
    }

    function instantiateITS(
        address impl
    )
        public virtual override
        returns (InterchainTokenService simulatedDeployment)
    {
        vm.startStateDiffRecording();
        simulatedDeployment = super.instantiateITS(impl);
        Vm.AccountAccess[] memory itsRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), itsRecords);
        copyContractState(address(simulatedDeployment), address(its), slots);
    }

    function instantiateITFImpl(
        address its_
    )
        public virtual override
        returns (InterchainTokenFactory simulatedDeployment)
    {
        simulatedDeployment = super.instantiateITFImpl(its_);
        // copy simulated state changes to target address in storage
        copyContractState(address(simulatedDeployment), address(itFactoryImpl), new bytes32[](0));
    }

    function instantiateITF(
        address impl
    )
        public virtual override
        returns (InterchainTokenFactory simulatedDeployment)
    {
        vm.startStateDiffRecording();
        simulatedDeployment = super.instantiateITF(impl);
        Vm.AccountAccess[] memory itfRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), itfRecords);
        copyContractState(address(simulatedDeployment), address(itFactory), slots);
    }

    /// TODO: convert to singleton for mainnet
    function instantiateRWTELImpl(address its_) public virtual override returns (RWTEL simulatedDeployment) {
        vm.startStateDiffRecording();
        simulatedDeployment = super.instantiateRWTELImpl(its_);
        Vm.AccountAccess[] memory rwtelImplRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), rwtelImplRecords);
        copyContractState(address(simulatedDeployment), address(rwTELImpl), slots);
    }

    /// TODO: convert to singleton for mainnet
    function instantiateRWTEL(address impl) public virtual override returns (RWTEL simulatedDeployment) {
        vm.startStateDiffRecording();
        simulatedDeployment = super.instantiateRWTEL(impl);
        simulatedDeployment.initialize(governanceAddress_, maxToClean, rwtelOwner);
        Vm.AccountAccess[] memory rwtelRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), rwtelRecords);
        copyContractState(address(simulatedDeployment), address(rwTEL), slots);
    }
}
