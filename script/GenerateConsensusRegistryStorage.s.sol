// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConsensusRegistry} from "src/consensus/ConsensusRegistry.sol";
import {IConsensusRegistry} from "src/consensus/interfaces/IConsensusRegistry.sol";

//todo: rename to generateConsensuRegistryGenesisConfig, update to inherit StorageDiffRecorder

/// @title ConsensusRegistry Genesis Storage Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values written by `initialize()`
/// Used by Telcoin-Network protocol to instantiate the contract with required configuration at genesis

/// @dev Usage: `forge script script/GenerateConsensusRegistryStorage.s.sol -vvvv`
contract GenerateConsensusRegistryStorage is Script, Test {
    ConsensusRegistry consensusRegistryImpl;
    ConsensusRegistry recordedRegistry;

    /// @dev Config: set all variables known outside of genesis time here
    address public rwTEL = address(0x7e1); //todo: this must be updated
    uint256 public stakeAmount = 1_000_000 ether;
    uint256 public minWithdrawAmount = 10_000 ether;
    IConsensusRegistry.ValidatorInfo[] initialValidators;
    address public owner = address(0x42);

    /// @dev Config: these will be overwritten into collision-resistant labels and replaced when known at genesis
    IConsensusRegistry.ValidatorInfo public validatorInfo1;
    IConsensusRegistry.ValidatorInfo public validatorInfo2;
    IConsensusRegistry.ValidatorInfo public validatorInfo3;
    IConsensusRegistry.ValidatorInfo public validatorInfo4;
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

    address public validator1 = address(0xbabe);
    address public validator2 = address(0xbeefbabe);
    address public validator3 = address(0xdeadbeefbabe);
    address public validator4 = address(0xc0ffeebabe);

    // misc utils
    bytes32[] writtenStorageSlots;
    bytes32 sharedBLSWord;

    function setUp() public {
        consensusRegistryImpl = new ConsensusRegistry();

        validator1BlsPubkey = abi.encodePacked(
            VALIDATOR_1_BLS_A,
            VALIDATOR_1_BLS_B,
            VALIDATOR_1_BLS_C
        );
        validator2BlsPubkey = abi.encodePacked(
            VALIDATOR_2_BLS_A,
            VALIDATOR_2_BLS_B,
            VALIDATOR_2_BLS_C
        );
        validator3BlsPubkey = abi.encodePacked(
            VALIDATOR_3_BLS_A,
            VALIDATOR_3_BLS_B,
            VALIDATOR_3_BLS_C
        );
        validator4BlsPubkey = abi.encodePacked(
            VALIDATOR_4_BLS_A,
            VALIDATOR_4_BLS_B,
            VALIDATOR_4_BLS_C
        );

        // populate `initialValidators` array with base struct from storage
        validatorInfo1 = IConsensusRegistry.ValidatorInfo(
            validator1BlsPubkey,
            validator1,
            uint32(0),
            uint32(0),
            uint24(1),
            IConsensusRegistry.ValidatorStatus.Active
        );
        initialValidators.push(validatorInfo1);

        validatorInfo2 = IConsensusRegistry.ValidatorInfo(
            validator2BlsPubkey,
            validator2,
            uint32(0),
            uint32(0),
            uint24(2),
            IConsensusRegistry.ValidatorStatus.Active
        );
        initialValidators.push(validatorInfo2);

        validatorInfo3 = IConsensusRegistry.ValidatorInfo(
            validator3BlsPubkey,
            validator3,
            uint32(0),
            uint32(0),
            uint24(3),
            IConsensusRegistry.ValidatorStatus.Active
        );
        initialValidators.push(validatorInfo3);

        validatorInfo4 = IConsensusRegistry.ValidatorInfo(
            validator4BlsPubkey,
            validator4,
            uint32(0),
            uint32(0),
            uint24(4),
            IConsensusRegistry.ValidatorStatus.Active
        );
        initialValidators.push(validatorInfo4);
    }

    function run() public {
        vm.startBroadcast();

        vm.startStateDiffRecording();
        recordedRegistry = ConsensusRegistry(
            payable(
                address(new ERC1967Proxy(address(consensusRegistryImpl), ""))
            )
        );
        recordedRegistry.initialize(
            address(rwTEL),
            stakeAmount,
            minWithdrawAmount,
            initialValidators,
            owner
        );
        Vm.AccountAccess[] memory records = vm.stopAndReturnStateDiff();

        // loop through all records to identify written storage slots so their final (current) value can later be read
        // this is necessary because `AccountAccess.storageAccesses` contains duplicates (due to re-writes on a slot)
        for (uint256 i; i < records.length; ++i) {
            // grab all slots with recorded state changes associated with `consensusRegistry`
            uint256 storageAccessesLen = records[i].storageAccesses.length;
            for (uint256 j; j < storageAccessesLen; ++j) {
                VmSafe.StorageAccess memory currentStorageAccess = records[i]
                    .storageAccesses[j];
                // sanity check the slot is relevant to registry
                assertEq(
                    currentStorageAccess.account,
                    address(recordedRegistry)
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
            "/deployments/genesis/consensus-registry-config.yaml"
        );
        vm.writeLine(dest, "---"); // indicate yaml format

        // read all unique storage slots touched by `initialize()` and fetch their final value
        for (uint256 i; i < writtenStorageSlots.length; ++i) {
            // load slot value
            bytes32 currentSlot = writtenStorageSlots[i];
            bytes32 slotValue = vm.load(address(recordedRegistry), currentSlot);

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
