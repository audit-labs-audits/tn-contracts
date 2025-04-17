// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import {StakeInfo} from "./IStakeManager.sol";

/**
 * @title ConsensusRegistry Interface
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract provides the interface for the Telcoin ConsensusRegistry smart contract
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
interface IConsensusRegistry {
    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint32 currentEpoch;
        uint8 epochPointer;
        EpochInfo[4] epochInfo;
        EpochInfo[4] futureEpochInfo;
        ValidatorInfo[] validators;
        uint256 numGenesisValidators;
        mapping(uint24 => uint24) tokenIdToIndex;
    }

    struct ValidatorInfo {
        bytes blsPubkey; // BLS public key is 48 bytes long; BLS proofs are 96 bytes
        address ecdsaPubkey;
        uint32 activationEpoch; // uint32 provides 3.7e14 years for 24hr epochs
        uint32 exitEpoch;
        uint24 tokenId;
        ValidatorStatus currentStatus;
    }

    struct EpochInfo {
        address[] committee;
        uint64 blockHeight;
    }

    error LowLevelCallFailure();
    error InvalidBLSPubkey();
    error InvalidECDSAPubkey();
    error InvalidProof();
    error InitializerArityMismatch();
    error InvalidCommitteeSize(
        uint256 minCommitteeSize,
        uint256 providedCommitteeSize
    );
    error CommitteeRequirement(address ecdsaPubkey);
    error NotValidator(address ecdsaPubkey);
    error AlreadyDefined(address ecdsaPubkey);
    error InvalidTokenId(uint256 tokenId);
    error InvalidStatus(ValidatorStatus status);
    error InvalidIndex(uint24 validatorIndex);
    error InvalidEpoch(uint32 epoch);

    event ValidatorPendingActivation(ValidatorInfo validator);
    event ValidatorActivated(ValidatorInfo validator);
    event ValidatorPendingExit(ValidatorInfo validator);
    event ValidatorExited(ValidatorInfo validator);
    event NewEpoch(EpochInfo epoch);
    event RewardsClaimed(address claimant, uint256 rewards);

    enum ValidatorStatus {
        Any,
        PendingActivation,
        Active,
        PendingExit,
        Exited
    }

    /// @notice Voting Validator Committee changes once every epoch
    /// @notice Can only be called in a `syscall` context, at the end of an epoch
    /// @dev Accepts the committee of voting validators for 2 epochs in the future
    /// @param newCommittee The future validator committee for 2 epochs after
    /// the current one is finalized; ie `$.currentEpoch + 3` (this func increments `currentEpoch`)
    function concludeEpoch(address[] calldata newCommittee) external;

    /// @dev Activates the calling validator, setting the next epoch as activation epoch
    /// @notice Caller must own the ConsensusNFT for their index and be pending activation status
    function activate() external;

    /// @dev Issues an exit request for a validator to be retired from the active validator set
    /// @notice Reverts if the caller would cause the network to lose BFT by exiting
    /// @notice Caller must be a validator with `ValidatorStatus.Active` status
    function beginExit() external;

    /// @dev Returns the current epoch
    function getCurrentEpoch() external view returns (uint32);

    /// @dev Returns information about the provided epoch. Only four latest & two future epochs are stored
    /// @notice When querying for future epochs, `blockHeight` will be 0 as they are not yet known
    function getEpochInfo(
        uint32 epoch
    ) external view returns (EpochInfo memory currentEpochInfo);

    /// @dev Returns an array of `ValidatorInfo` structs that match the provided status for this epoch
    function getValidators(
        ValidatorStatus status
    ) external view returns (ValidatorInfo[] memory);

    /// @dev Fetches the `validatorIndex` for a given validator address
    /// @notice A returned `validatorIndex` value of `0` is invalid and indicates
    /// that the given address is not a known validator's ECDSA pubkey
    function getValidatorIndex(
        address ecdsaPubkey
    ) external view returns (uint24 validatorIndex);

    /// @dev Fetches the `ValidatorInfo` for a given validator index
    /// @notice To enable checks against storage slots initialized to zero by the EVM, `validatorIndex` cannot be `0`
    function getValidatorByIndex(
        uint24 validatorIndex
    ) external view returns (ValidatorInfo memory validator);
}
