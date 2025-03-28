// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
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
import { AxelarGasServiceProxy } from "../../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../../../src/WTEL.sol";
import { RWTEL } from "../../../src/RWTEL.sol";
import { ExtCall } from "../../../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "../../../deployments/utils/Create3Utils.sol";
import { Deployments } from "../../../deployments/Deployments.sol";
import { ITSUtils } from "../../../deployments/utils/ITSUtils.sol";

/// @title Interchain Token Service Genesis Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values
/// Used by Telcoin-Network protocol to instantiate the contracts with required configuration at genesis

/// @dev Usage: `forge script script/GenerateConsensusRegistryStorage.s.sol -vvvv`
contract GenerateITSConfig is Script, Test {
    Create3Deployer create3;
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

    /// @dev Config: set all variables known outside of genesis time here
    address public rwTEL = address(0x7e1);
    uint256 public stakeAmount = 1_000_000 ether;
    uint256 public minWithdrawAmount = 10_000 ether;
    IConsensusRegistry.ValidatorInfo[] initialValidators;
    address public owner = address(0x42);

    /// @dev Config: these will be overwritten into collision-resistant labels and replaced when known at genesis
    // todo: probably not needed, since only storage is proxy & owner slots

    // misc utils
    bytes32[] writtenStorageSlots;
    bytes32 sharedBLSWord;

    function setUp() public {
        // setup config for TN <> sepolia
        //todo: testnet, mainnet etc
    }

    function run() public {
        vm.startBroadcast();

        vm.startStateDiffRecording();
        // todo: maybe create an abstract function that can be used for each deployment?
        // record _create3Deploy all ITS, save new contracts + their bytecode + their storage if relevant

        Vm.AccountAccess[] memory records = vm.stopAndReturnStateDiff();

        // loop through all records to identify written storage slots so their final (current) value can later be read
        // this is necessary because `AccountAccess.storageAccesses` contains duplicates (due to re-writes on a slot)
        for (uint256 i; i < records.length; ++i) {
            // grab all slots with recorded state changes associated with `consensusRegistry`
            uint256 storageAccessesLen = records[i].storageAccesses.length;
            for (uint256 j; j < storageAccessesLen; ++j) {
                VmSafe.StorageAccess memory currentStorageAccess = records[i]
                    .storageAccesses[j];
                // sanity check the slot is relevant to current contract
                assertEq(
                    currentStorageAccess.account,
                    address(recordedRegistry) //todo: current contract (loop of abstraction?)
                );

                if (currentStorageAccess.isWrite) {
                    // check `writtenStorageSlots` to skip duplicates, since some slots are updated multiple times
                    bool isDuplicate;
                    for (uint256 k; k < writtenStorageSlots.length; ++k) {
                        if (
                            writtenStorageSlots[k] == currentStorageAccess.slot
                        ) {
                            isDuplicate = true;
                            break;
                        }
                    }

                    // store non-duplicate storage slots to read from later
                    if (!isDuplicate) {
                        writtenStorageSlots.push(currentStorageAccess.slot);
                    }
                }
            }
        }

        string memory root = vm.projectRoot();
        string memory dest = string.concat(
            root,
            "/deployments/its-config.yaml" //todo: new yaml
        );
        vm.writeLine(dest, "---"); // indicate yaml format

        // read all unique storage slots touched by `initialize()` and fetch their final value
        for (uint256 i; i < writtenStorageSlots.length; ++i) {
            // load slot value
            bytes32 currentSlot = writtenStorageSlots[i];
            bytes32 slotValue = vm.load(address(recordedRegistry), currentSlot);

            //todo: prob not necessary
            // check if value is a validator ecdsaPubkey and assign collision-resistant label for replacement
            if (uint256(slotValue) == uint256(uint160(validator1))) {
                slotValue = keccak256("VALIDATOR_1_ECDSA");
            } else if (uint256(slotValue) == uint256(uint160(validator2))) {
                slotValue = keccak256("VALIDATOR_2_ECDSA");
            } else if (uint256(slotValue) == uint256(uint160(validator3))) {
                slotValue = keccak256("VALIDATOR_3_ECDSA");
            } else if (uint256(slotValue) == uint256(uint160(validator4))) {
                slotValue = keccak256("VALIDATOR_4_ECDSA");
            }

            // write slot and value to file
            string memory slot = LibString.toHexString(
                uint256(currentSlot),
                32
            );
            string memory value = LibString.toHexString(uint256(slotValue), 32);
            string memory entry = string.concat(slot, ": ", value);

            vm.writeLine(dest, entry);
        }

        vm.stopBroadcast();
    }
}
