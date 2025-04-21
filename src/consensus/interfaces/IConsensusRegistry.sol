// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { StakeInfo } from "./IStakeManager.sol";

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
        uint32 currentEpoch; // uint32 provides 3.7e14 years for 24hr epochs
        uint8 epochPointer;
        EpochInfo[4] epochInfo;
        EpochInfo[4] futureEpochInfo;
        mapping(uint24 => ValidatorInfo) validators;
        mapping(address => address) delegations; //todo must be wiped clean on unstake/retirement
    }

    struct ValidatorInfo {
        bytes blsPubkey; // using uncompressed 96 byte BLS public keys
        address ecdsaPubkey;
        uint32 activationEpoch;
        uint32 exitEpoch;
        ValidatorStatus currentStatus;
        bool isRetired;
        bool isDelegated; // todo: require validator.ecdsaPubkey sig for no DOS
        uint8 stakeVersion;
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
    error InvalidCommitteeSize(uint256 minCommitteeSize, uint256 providedCommitteeSize);
    error CommitteeRequirement(address ecdsaPubkey);
    error NotValidator(address ecdsaPubkey);
    error AlreadyDefined(address ecdsaPubkey);
    error InvalidStatus(ValidatorStatus status);
    error InvalidEpoch(uint32 epoch);

    event ValidatorStaked(ValidatorInfo validator);
    event ValidatorPendingActivation(ValidatorInfo validator);
    event ValidatorActivated(ValidatorInfo validator);
    event ValidatorPendingExit(ValidatorInfo validator);
    event ValidatorExited(ValidatorInfo validator);
    event ValidatorRetired(ValidatorInfo validator);
    event NewEpoch(EpochInfo epoch);
    event RewardsClaimed(address claimant, uint256 rewards);

    enum ValidatorStatus {
        Any,
        Staked,
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
    function concludeEpoch(address[] calldata newCommittee) external returns (ValidatorInfo[] memory);

    /// @dev Activates the calling validator, setting the next epoch as activation epoch
    /// to ensure ineligibility for rewards until completing a full epoch
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
    function getEpochInfo(uint32 epoch) external view returns (EpochInfo memory currentEpochInfo);

    /// @dev Returns an array of `ValidatorInfo` structs that match the provided status for this epoch
    function getValidators(ValidatorStatus status) external view returns (ValidatorInfo[] memory);

    /// @dev Fetches the `tokenId` for a given validator ecdsaPubkey
    function getValidatorTokenId(address ecdsaPubkey) external view returns (uint256);

    /// @dev Fetches the `ValidatorInfo` for a given ConsensusNFT tokenId
    /// @notice To enable checks against storage slots initialized to zero by the EVM, `tokenId` cannot be `0`
    function getValidatorByTokenId(uint256 tokenId) external view returns (ValidatorInfo memory);

    /// @dev Returns whether validator associated with `tokenId` is exited && unstaked, ie "retired"
    /// @notice Retired validators' ConsensusNFTs are burned, so existing tokenIds are invalid
    function isRetired(uint256 tokenId) external view returns (bool);
}
