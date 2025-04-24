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
    /// `genesisTarget`: 
    ///   `bytecode`: `simulatedDeployment.code`
    ///   `storage:`: 
    ///      `slotA: slotAValue`
    ///      `slotB: slotBValue`
    /// @param simulatedDeployment The deployed contract with storage written by simulation
    /// @param genesisTarget The target address to write to at genesis
    function yamlAppendBytecodeWithStorage(string memory dest, address simulatedDeployment, address genesisTarget) public virtual {
    // Convert  genesisTarget to hex string (20 bytes, i.e. address) and write
    string memory targetKey = LibString.toHexString(uint256(uint160(genesisTarget)), 20);
    vm.writeLine(dest, string.concat(targetKey, ":"));

    // Get bytecode of the simulated deployment
    bytes memory bytecode = simulatedDeployment.code;
    string memory codeString = LibString.toHexString(bytecode);

    // Write the bytecode & storage with 2-space indentation
    vm.writeLine(dest, string.concat("  bytecode: ", codeString));
    vm.writeLine(dest, "  storage:");

    bytes32[] storage slots = writtenStorageSlots[simulatedDeployment];
    require(slots.length != 0, "No storage diffs found");

    // Write each storage slot line with 4-space indentation
    for (uint256 i; i < slots.length; ++i) {
        bytes32 currentSlot = slots[i];
        bytes32 slotValue = vm.load(simulatedDeployment, currentSlot);

        string memory slot = LibString.toHexString(uint256(currentSlot), 32);
        string memory value = LibString.toHexString(uint256(slotValue), 32);

        vm.writeLine(dest, string.concat("    ", slot, ": ", value));
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
        // write top level entry using the desired address and the simulated contract's bytecode
        string memory key = string.concat(LibString.toHexString(genesisTarget), ":");
        vm.writeLine(dest, key);
        string memory codeString = LibString.toHexString(bytecode);
        string memory bytecodeEntry = string.concat("  bytecode: ", codeString);
        vm.writeLine(dest, bytecodeEntry);
    }
}