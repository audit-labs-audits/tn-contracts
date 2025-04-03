// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title Storage Diff Recorder
/// @notice Used to record storage slots and their values written by a deployment simulation
/// Used to derive values for instantiating contracts with required configuration at genesis

abstract contract StorageDiffRecorder is Test {
    mapping (address => bytes32[]) writtenStorageSlots;

    /// @dev Populates `writtenStorageSlots` with written storage slots in `records`
    /// @param simulatedDeployment The deployed contract with storage written by simulation
    /// @param records The AccountAccesses recorded by foundry diff 
    function saveWrittenSlots(address simulatedDeployment, Vm.AccountAccess[] memory records) public virtual returns (bytes32[] memory) {
        bytes32[] storage slots = writtenStorageSlots[simulatedDeployment];
        require(slots.length == 0, "Must clear storage array before populating");

        // loop through all records to identify written storage slots so their final (current) value can later be read
        for (uint256 i; i < records.length; ++i) {
            // grab all slots with recorded state changes
            uint256 storageAccessesLen = records[i].storageAccesses.length;
            for (uint256 j; j < storageAccessesLen; ++j) {
                VmSafe.StorageAccess memory currentStorageAccess = records[i]
                    .storageAccesses[j];
                // skip records not relevant to requested contract
                if (currentStorageAccess.account != simulatedDeployment) continue;

                if (currentStorageAccess.isWrite) {
                    // check `slots` to skip duplicates, since some slots are updated multiple times
                    bool isDuplicate;
                    for (uint256 k; k < slots.length; ++k) {
                        if (
                            slots[k] == currentStorageAccess.slot
                        ) {
                            isDuplicate = true;
                            break;
                        }
                    }

                    // store non-duplicate storage slots to read from later
                    if (!isDuplicate) {
                        slots.push(currentStorageAccess.slot);
                    }
                }
            }
        }

        return slots;
    }

    /// @dev Copies runtime bytecode and the given storage slots from one address to another
    function copyContractState(address from, address to, bytes32[] memory slotsToCopy) public {
        vm.etch(to, from.code);

        for (uint256 i; i < slotsToCopy.length; ++i) {
            bytes32 slotToCopy = slotsToCopy[i];
            bytes32 valueToCopy = vm.load(from, slotToCopy);
            vm.store(to, slotToCopy, valueToCopy);
        }
    }

    /// @dev Appends a genesis config entry with bytecode & storage to given YAML file 
    /// @dev Uses current `writtenStorageSlots` values; simulation results must be populated correctly
    /// @notice Entries are formatted thusly:
    /// `genesisTarget`: `simulatedDeployment.code`
    ///   `writtenStorageSlotA`: `currentSlotAValueAfterSimulation`
    ///   `writtenStorageSlotB`: `currentSlotBValueAfterSimulation`
    /// @param simulatedDeployment The deployed contract with storage written by simulation
    /// @param genesisTarget The target address to write to at genesis
    function yamlAppendBytecodeWithStorage(string memory dest, address simulatedDeployment, address genesisTarget) public virtual {
        yamlAppendBytecode(dest, simulatedDeployment, genesisTarget);

        bytes32[] storage slots = writtenStorageSlots[simulatedDeployment];
        require(slots.length != 0, "No storage diffs found");
        // read all unique storage slots updated and fetch their final value
        for (uint256 i; i < slots.length; ++i) {
            // load slot value
            bytes32 currentSlot = slots[i];
            bytes32 slotValue = vm.load(simulatedDeployment, currentSlot);

            // write slot and value to file
            string memory slot = LibString.toHexString(
                uint256(currentSlot),
                32
            );
            string memory value = LibString.toHexString(uint256(slotValue), 32);
            // prepend with 2 spaces to list current slot and value as object members under top level entry
            string memory entry = string.concat("  ", slot, ": ", value);

            vm.writeLine(dest, entry);
        }
    }

    /// @dev Appends a genesis config entry with bytecode only to the given YAML. Required for immutable vars
    /// @notice Entries are formatted thusly:
    /// `genesisTarget`: `simulatedDeployment.code`
    /// @param simulatedDeployment The deployed contract with bytecode  by simulation
    /// @param genesisTarget The target address to write to at genesis
    function yamlAppendBytecode(string memory dest, address simulatedDeployment, address genesisTarget) public virtual {
        bytes memory bytecode = simulatedDeployment.code;
        require(bytecode.length != 0, "Contract is not deployed");
        string memory runtimeCode = LibString.toHexString(bytecode);
        // write top level entry using the desired address and the simulated contract's bytecode
        string memory addressToBytecode = string.concat(LibString.toHexString(genesisTarget), ": ", runtimeCode);
        vm.writeLine(dest, addressToBytecode);
    }
}