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
    /// @param simulatedAccount The deployed contract with storage written by simulation
    /// @param records The AccountAccesses recorded by foundry diff 
    function getWrittenSlots(address simulatedAccount, Vm.AccountAccess[] memory records) public virtual {
        bytes32[] storage slots = writtenStorageSlots[simulatedAccount];
        require(slots.length == 0, "Must clear storage array before populating");

        // loop through all records to identify written storage slots so their final (current) value can later be read
        for (uint256 i; i < records.length; ++i) {
            // grab all slots with recorded state changes
            uint256 storageAccessesLen = records[i].storageAccesses.length;
            for (uint256 j; j < storageAccessesLen; ++j) {
                VmSafe.StorageAccess memory currentStorageAccess = records[i]
                    .storageAccesses[j];
                // skip records not relevant to requested contract
                if (currentStorageAccess.account != simulatedAccount) continue;

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
    }

    /// @dev Appends a genesis config entry with bytecode & storage to given YAML file 
    /// @dev Uses current `writtenStorageSlots` values; simulation results must be populated correctly
    /// @notice Entries are formatted thusly:
    /// `desiredTarget`: `simulatedAccount.code`
    ///   `writtenStorageSlotA`: `currentSlotAValueAfterSimulation`
    ///   `writtenStorageSlotB`: `currentSlotBValueAfterSimulation`
    /// @param simulatedAccount The deployed contract with storage written by simulation
    /// @param desiredTarget The target address to write to at genesis
    function yamlAppendBytecodeWithStorage(string memory dest, address simulatedAccount, address desiredTarget) public virtual {
        yamlAppendBytecode(dest, simulatedAccount, desiredTarget);

        bytes32[] storage slots = writtenStorageSlots[simulatedAccount];
        require(slots.length != 0, "No storage diffs found");
        // read all unique storage slots updated and fetch their final value
        for (uint256 i; i < slots.length; ++i) {
            // load slot value
            bytes32 currentSlot = slots[i];
            bytes32 slotValue = vm.load(simulatedAccount, currentSlot);

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
    /// `desiredTarget`: `simulatedAccount.code`
    /// @param simulatedAccount The deployed contract with bytecode  by simulation
    /// @param desiredTarget The target address to write to at genesis
    function yamlAppendBytecode(string memory dest, address simulatedAccount, address desiredTarget) public virtual {
        bytes memory bytecode = simulatedAccount.code;
        require(bytecode.length != 0, "Contract is not deployed");
        string memory runtimeCode = LibString.toHexString(bytecode);
        // write top level entry using the desired address and the simulated contract's bytecode
        string memory addressToBytecode = string.concat(LibString.toHexString(desiredTarget), ": ", runtimeCode);
        vm.writeLine(dest, addressToBytecode);
    }
}