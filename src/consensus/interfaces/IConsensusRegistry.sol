// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { StakeInfo } from "./interfaces/IStakeManager.sol";

/**
 * @title ConsensusRegistry Interface
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract provides the interface for the Telcoin ConsensusRegistry smart contract
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
interface IConsensusRegistry {

/*
ConsensusRegistry storage layout for genesis
| Name             | Type                          | Slot                                                               | Offset | Bytes |
|------------------|-------------------------------|--------------------------------------------------------------------|--------|-------|
| _paused          | bool                          | 0                                                                  | 0      | 1     |
| _owner           | address                       | 0                                                                  | 1      | 20    |
|------------------|-------------------------------|--------------------------------------------------------------------|--------|-------|
| rwTEL            | address                       | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400 | 12     | 20    |
| stakeAmount      | uint256                       | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7401 | 0      | 32    |
| minWithdrawAmount| uint256                       | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7402 | 0      | 32    |
| stakeInfo        | mapping(address => StakeInfo) | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7403 | 0      | s     |
|------------------|-------------------------------|--------------------------------------------------------------------|--------|-------|
| currentEpoch     | uint32                        | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100 | 0      | 4     |
| epochPointer     | uint8                         | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100 | 4      | 1     |
| epochInfo        | EpochInfo[4]                  | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23101 | 0      | x     |
| futureEpochInfo  | FutureEpochInfo[4]            | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23102 | 0      | y     |
| validators       | ValidatorInfo[]               | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23103 | 0      | z     |

Storage locations for dynamic variables 
- `stakeInfo` content (s) begins at slot `0x3b2018e21a7d1a934ee474879a6c46622c725c81fe1ab37a62fbdda1c85e54e4`
- `epochInfo` (x) begins at slot `0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39` as abi-encoded
representation
- `futureEpochInfo` (y) begins at slot `0x3e15a0612117eb21841fac9ea1ce6cd116a911fe4c91a9c367a82cd0c3d79718` as abi-encoded
representation
- `validators` (z) begins at slot `0x96a201c8a417846842c79be2cd1e33440471871a6cf94b34c8f286aaeb24ad6b` as abi-encoded
representation
*/

    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint32 currentEpoch;
        uint8 epochPointer;
        EpochInfo[4] epochInfo;
        FutureEpochInfo[4] futureEpochInfo;
        ValidatorInfo[] validators;
    }

    struct ValidatorInfo {
        bytes blsPubkey; // BLS public key is 48 bytes long; BLS proofs are 96 bytes
        bytes32 ed25519Pubkey;
        address ecdsaPubkey;
        uint32 activationEpoch; // uint32 provides ~22000yr for 160s epochs (5s rounds)
        uint32 exitEpoch;
        uint16 validatorIndex; // up to 65535 validators
        bytes4 unused; // can be used for other data as well as expanded against activation and exit members
        ValidatorStatus currentStatus;
    }

    struct EpochInfo {
        address[] committee;
        uint64 blockHeight;
    }

    /// @dev Used to populate a separate ring buffer to prevent overflow conditions when writing future state
    struct FutureEpochInfo {
        address[] committee;
    }

    error LowLevelCallFailure();
    error InvalidBLSPubkey();
    error InvalidEd25519Pubkey();
    error InvalidECDSAPubkey();
    error InvalidProof();
    error InitializerArityMismatch();
    error InvalidCommitteeSize(uint256 minCommitteeSize, uint256 providedCommitteeSize);
    error NotValidator(address ecdsaPubkey);
    error AlreadyDefined(address ecdsaPubkey);
    error InvalidStatus(ValidatorStatus status);
    error InvalidIndex(uint16 validatorIndex);
    error InvalidEpoch(uint32 epoch);

    event ValidatorPendingActivation(ValidatorInfo validator);
    event ValidatorActivated(ValidatorInfo validator);
    event ValidatorPendingExit(ValidatorInfo validator);
    event ValidatorExited(ValidatorInfo validator);
    event NewEpoch(EpochInfo epoch);
    event RewardsClaimed(address claimant, uint256 rewards);

    enum ValidatorStatus {
        Undefined,
        PendingActivation,
        Active,
        PendingExit,
        Exited
    }

    /// @notice Voting Validator Committee changes once every epoch (== 32 rounds)
    /// @notice Can only be called in a `syscall` context
    /// @dev Accepts the committee of voting validators for 2 epochs in the future and 
    /// staking reward info for the previous epoch to finalize
    /// @param newCommitteeIndices The future validator committee for 2 epochs after 
    /// the current one is finalized; ie `$.currentEpoch + 3` (this func increments `currentEpoch`)
    /// @param stakingRewardInfos Staking reward info defining which validators to reward 
    /// and how much each rewardee earned for the current epoch 
    function finalizePreviousEpoch(
        address[] calldata newCommitteeIndices, // todo: change to addresses && todo: this array refers to 2 epochs forward, if currentepoch == 0 || 1 special case 
        StakeInfo[] calldata stakingRewardInfos
    )
        external
        returns (uint32 newEpoch, uint256 numActiveValidators);

    /// @dev Issues an exit request for a validator to be ejected from the active validator set
    function exit() external;

    /// @dev Returns the current epoch
    function getCurrentEpoch() external view returns (uint32);

    /// @dev Returns information about the provided epoch. Only four latest epochs are stored + accessible
    function getEpochInfo(uint32 epoch) external view returns (EpochInfo memory currentEpochInfo);

    /// @dev Returns an array of `ValidatorInfo` structs that match the provided status for this epoch
    function getValidators(ValidatorStatus status) external view returns (ValidatorInfo[] memory);

    /// @dev Fetches the `validatorIndex` for a given validator address
    /// @notice A returned `validatorIndex` value of `0` is invalid and indicates
    /// that the given address is not a known validator's ECDSA externalkey
    function getValidatorIndex(address ecdsaPubkey) external view returns (uint16 validatorIndex);

    /// @dev Fetches the `ValidatorInfo` for a given validator index
    /// @notice To enable checks against storage slots initialized to zero by the EVM, `validatorIndex` cannot be `0`
    function getValidatorByIndex(uint16 validatorIndex) external view returns (ValidatorInfo memory validator);
}
