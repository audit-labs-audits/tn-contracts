// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { StakeInfo } from "./StakeManager.sol";

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
| rwTEL            | address                       | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100 | 12      | 20    |
| stakeAmount      | uint256                       | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23101 | 0      | 32    |
| minWithdrawAmount| uint256                       | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23102 | 0      | 32    |
| currentEpoch     | uint32                        | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23103 | 0      | 4     |
| epochPointer     | uint8                         | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23103 | 4      | 1     |
| epochInfo        | EpochInfo[4]                  | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23104 | 0      | x     |
| stakeInfo        | mapping(address => StakeInfo) | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23105 | 0      | y     |
| validators       | ValidatorInfo[]               | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23106 | 0      | z     |

- `epochInfo` begins at slot `0x96a201c8a417846842c79be2cd1e33440471871a6cf94b34c8f286aaeb24ad6b` as abi-encoded
representation
    - `stakeInfo` content begins at slot `0x6c559f44aaff501c8c4572f1fe564ba609cd362de315d1241502f2e0437459c2`
- `validators` begins at slot `0x14d1f3ad8599cd8151592ddeade449f790add4d7065a031fbe8f7dbb1833e0a9` as abi-encoded
representation
*/

    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint32 currentEpoch;
        uint8 epochPointer;
        EpochInfo[4] epochInfo;
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
        uint16[] committeeIndices; // voter committee's validator indices
        uint64 blockHeight;
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
    /// @dev Accepts the new epoch's committee of voting validators, which have been ascertained as active via handshake
    function finalizePreviousEpoch(
        uint64 numBlocks,
        uint16[] calldata newCommitteeIndices,
        StakeInfo[] calldata stakingRewardInfos
    )
        external
        returns (uint32 newEpoch, uint64 newBlockHeight, uint256 numActiveValidators);

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
