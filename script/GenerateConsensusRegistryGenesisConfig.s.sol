// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { IConsensusRegistry } from "src/consensus/interfaces/IConsensusRegistry.sol";
import { IStakeManager } from "src/consensus/interfaces/IStakeManager.sol";
import { Deployments } from "../deployments/Deployments.sol";
import { StorageDiffRecorder } from "../deployments/genesis/StorageDiffRecorder.sol";

/// @title ConsensusRegistry Genesis Storage Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values written by `initialize()`
/// Used by Telcoin-Network protocol to instantiate the contract with required configuration at genesis

/// @dev Usage: `forge script script/GenerateConsensusRegistryGenesisConfig.s.sol -vvvv`
contract GenerateConsensusRegistryGenesisConfig is Script, StorageDiffRecorder {
    ConsensusRegistry consensusRegistryImpl;
    ConsensusRegistry consensusRegistry;

    Deployments deployments;
    string root;
    string dest;
    string fileName = "/deployments/genesis/consensus-registry-config.yaml";

    /// @dev Config: set all variables known outside of genesis time here
    address public rwTEL;
    uint256 public stakeAmount = 1_000_000 ether;
    uint256 public minWithdrawAmount = 1000 ether;
    uint256 public epochIssuance = 714_285_714_285_714_285_714_285; // 20_000_000 TEL per month at 1 day epochs
    uint32 public epochDuration = 24 hours;
    IConsensusRegistry.ValidatorInfo[] initialValidators;
    address public owner;

    IConsensusRegistry.ValidatorInfo public validatorInfo1;
    IConsensusRegistry.ValidatorInfo public validatorInfo2;
    IConsensusRegistry.ValidatorInfo public validatorInfo3;
    IConsensusRegistry.ValidatorInfo public validatorInfo4;
    IConsensusRegistry.ValidatorInfo public validatorInfo5;

    /// @dev These flags will be overwritten into collision-resistant labels and replaced when known at genesis
    bytes32 constant VALIDATOR_1_BLS_A = keccak256("VALIDATOR_1_BLS_A");
    bytes32 constant VALIDATOR_1_BLS_B = keccak256("VALIDATOR_1_BLS_B");
    bytes32 constant VALIDATOR_1_BLS_C = keccak256("VALIDATOR_1_BLS_C");
    bytes validator1BlsPubkey;

    bytes32 constant VALIDATOR_2_BLS_A = keccak256("VALIDATOR_2_BLS_A");
    bytes32 constant VALIDATOR_2_BLS_B = keccak256("VALIDATOR_2_BLS_B");
    bytes32 constant VALIDATOR_2_BLS_C = keccak256("VALIDATOR_2_BLS_C");
    bytes validator2BlsPubkey;

    bytes32 constant VALIDATOR_3_BLS_A = keccak256("VALIDATOR_3_BLS_A");
    bytes32 constant VALIDATOR_3_BLS_B = keccak256("VALIDATOR_3_BLS_B");
    bytes32 constant VALIDATOR_3_BLS_C = keccak256("VALIDATOR_3_BLS_C");
    bytes validator3BlsPubkey;

    bytes32 constant VALIDATOR_4_BLS_A = keccak256("VALIDATOR_4_BLS_A");
    bytes32 constant VALIDATOR_4_BLS_B = keccak256("VALIDATOR_4_BLS_B");
    bytes32 constant VALIDATOR_4_BLS_C = keccak256("VALIDATOR_4_BLS_C");
    bytes validator4BlsPubkey;

    bytes32 constant VALIDATOR_5_BLS_A = keccak256("VALIDATOR_5_BLS_A");
    bytes32 constant VALIDATOR_5_BLS_B = keccak256("VALIDATOR_5_BLS_B");
    bytes32 constant VALIDATOR_5_BLS_C = keccak256("VALIDATOR_5_BLS_C");
    bytes validator5BlsPubkey;

    address public validator1 = address(0xbabe);
    address public validator2 = address(0xbeefbabe);
    address public validator3 = address(0xdeadbeefbabe);
    address public validator4 = address(0xc0ffeebabe);
    address public validator5 = address(0xc0c0a);

    // ConsensusRegistry initialization
    bytes initData;

    function setUp() public {
        root = vm.projectRoot();
        dest = string.concat(root, fileName);
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        _setGenesisTargets(deployments.rwTEL, deployments.ConsensusRegistryImpl, deployments.ConsensusRegistry);
        _setInitialValidators();

        owner = deployments.admin;
        IStakeManager.StakeConfig memory genesisConfig = IStakeManager.StakeConfig(
            stakeAmount,
            minWithdrawAmount,
            epochIssuance,
            epochDuration
        );
        initData = abi.encodeWithSelector(
            ConsensusRegistry.initialize.selector,
            address(rwTEL),
            genesisConfig,
            initialValidators,
            owner
        );
    }

    function run() public {
        vm.startBroadcast();

        // initialize clean yaml file
        if (vm.exists(dest)) vm.removeFile(dest);
        vm.writeLine(dest, "---"); // indicate yaml format

        address simulatedCRImpl = address(instantiateConsensusRegistryImpl());
        yamlAppendBytecode(dest, simulatedCRImpl, deployments.ConsensusRegistryImpl);

        address simulatedCR = address(instantiateConsensusRegistry(deployments.ConsensusRegistryImpl, initData));
        overwriteWrittenStorageSlotsWithFlags(simulatedCR);
        yamlAppendBytecodeWithStorage(dest, simulatedCR, deployments.ConsensusRegistry);

        vm.stopBroadcast();
    }

    function _setGenesisTargets(address rwtel, address impl, address proxy) internal {
        rwTEL = rwtel;
        consensusRegistryImpl = ConsensusRegistry(impl);
        consensusRegistry = ConsensusRegistry(proxy);
    }

    function _setInitialValidators() internal {
        validator1BlsPubkey = abi.encodePacked(VALIDATOR_1_BLS_A, VALIDATOR_1_BLS_B, VALIDATOR_1_BLS_C);
        validator2BlsPubkey = abi.encodePacked(VALIDATOR_2_BLS_A, VALIDATOR_2_BLS_B, VALIDATOR_2_BLS_C);
        validator3BlsPubkey = abi.encodePacked(VALIDATOR_3_BLS_A, VALIDATOR_3_BLS_B, VALIDATOR_3_BLS_C);
        validator4BlsPubkey = abi.encodePacked(VALIDATOR_4_BLS_A, VALIDATOR_4_BLS_B, VALIDATOR_4_BLS_C);
        validator5BlsPubkey = abi.encodePacked(VALIDATOR_5_BLS_A, VALIDATOR_5_BLS_B, VALIDATOR_5_BLS_C);

        // populate `initialValidators` array with base struct from storage
        validatorInfo1 = IConsensusRegistry.ValidatorInfo(
            validator1BlsPubkey,
            validator1,
            uint32(0),
            uint32(0),
            IConsensusRegistry.ValidatorStatus.Active,
            false,
            false,
            uint8(0)
        );
        initialValidators.push(validatorInfo1);

        validatorInfo2 = IConsensusRegistry.ValidatorInfo(
            validator2BlsPubkey,
            validator2,
            uint32(0),
            uint32(0),
            IConsensusRegistry.ValidatorStatus.Active,
            false,
            false,
            uint8(0)
        );
        initialValidators.push(validatorInfo2);

        validatorInfo3 = IConsensusRegistry.ValidatorInfo(
            validator3BlsPubkey,
            validator3,
            uint32(0),
            uint32(0),
            IConsensusRegistry.ValidatorStatus.Active,
            false,
            false,
            uint8(0)
        );
        initialValidators.push(validatorInfo3);

        validatorInfo4 = IConsensusRegistry.ValidatorInfo(
            validator4BlsPubkey,
            validator4,
            uint32(0),
            uint32(0),
            IConsensusRegistry.ValidatorStatus.Active,
            false,
            false,
            uint8(0)
        );
        initialValidators.push(validatorInfo4);

        validatorInfo5 = IConsensusRegistry.ValidatorInfo(
            validator5BlsPubkey,
            validator5,
            uint32(0),
            uint32(0),
            IConsensusRegistry.ValidatorStatus.Active,
            false,
            false,
            uint8(0)
        );
        initialValidators.push(validatorInfo5);
    }

    function instantiateConsensusRegistryImpl() public virtual returns (ConsensusRegistry simulatedDeployment) {
        vm.startStateDiffRecording();
        simulatedDeployment = new ConsensusRegistry();
        Vm.AccountAccess[] memory crImplRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), crImplRecords);
        copyContractState(address(simulatedDeployment), address(consensusRegistryImpl), slots);
    }

    function instantiateConsensusRegistry(
        address impl,
        bytes memory initCall
    )
        public
        virtual
        returns (ConsensusRegistry simulatedDeployment)
    {
        vm.startStateDiffRecording();
        simulatedDeployment = ConsensusRegistry(
            payable(address(new ERC1967Proxy{ value: stakeAmount * initialValidators.length }(impl, initCall)))
        );
        Vm.AccountAccess[] memory crRecords = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = saveWrittenSlots(address(simulatedDeployment), crRecords);
        copyContractState(address(simulatedDeployment), address(consensusRegistry), slots);
    }

    function overwriteWrittenStorageSlotsWithFlags(address simulatedCR) public {
        // read all unique storage slots touched by `initialize()` and fetch their final value
        bytes32[] storage slots = writtenStorageSlots[simulatedCR];
        for (uint256 i; i < slots.length; ++i) {
            // load slot value
            bytes32 currentSlot = slots[i];
            bytes32 slotValue = vm.load(simulatedCR, currentSlot);

            // check if value is a validator address and assign collision-resistant label for replacement
            if (uint256(slotValue) == uint256(uint160(validator1))) {
                slotValue = keccak256("VALIDATOR_1_ADDR");
            } else if (uint256(slotValue) == uint256(uint160(validator2))) {
                slotValue = keccak256("VALIDATOR_2_ADDR");
            } else if (uint256(slotValue) == uint256(uint160(validator3))) {
                slotValue = keccak256("VALIDATOR_3_ADDR");
            } else if (uint256(slotValue) == uint256(uint160(validator4))) {
                slotValue = keccak256("VALIDATOR_4_ADDR");
            } else if (uint256(slotValue) == uint256(uint160(validator5))) {
                slotValue = keccak256("VALIDATOR_5_ADDR");
            }

            // overwrite current storage slot
            vm.store(simulatedCR, currentSlot, slotValue);
        }
    }
}
