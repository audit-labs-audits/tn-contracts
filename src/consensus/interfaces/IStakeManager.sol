// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

/**
 * @title IStakeManager
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This interface declares the ConsensusRegistry's staking API and data structures
 * @dev Implemented within StakeManager.sol, which is inherited by the ConsensusRegistry
 */
struct StakeInfo {
    uint24 tokenId;
    uint232 stakingRewards;
}

interface IStakeManager {
    /// @custom:storage-location erc7201:telcoin.storage.StakeManager
    struct StakeManagerStorage {
        address rwTEL;
        uint24 totalSupply;
        uint8 stakeVersion;
        mapping(uint8 => StakeConfig) versions;
        mapping(address => StakeInfo) stakeInfo;
        mapping(address => address) delegations; //todo: work this in
    }

    struct StakeConfig {
        uint256 stakeAmount;
        uint256 minWithdrawAmount;
        uint256 consensusBlockReward;
    }

    error InvalidTokenId(uint256 tokenId);
    error InvalidStakeAmount(uint256 stakeAmount);
    error InsufficientRewards(uint256 withdrawAmount);
    error NotTransferable();
    error RequiresConsensusNFT();

    /// @dev Accepts the stake amount of native TEL and issues an activation request for the caller (validator)
    /// @notice Caller must already have been issued a `ConsensusNFT` by Telcoin governance
    function stake(bytes calldata blsPubkey) external payable;

    /// @dev Increments the claimable rewards for each validator
    /// @notice May only be called by the client via system call, at the start of a new epoch
    /// @param stakingRewardInfos Staking reward info defining which validators to reward
    /// and how much each rewardee earned for the current epoch
    function incrementRewards(StakeInfo[] calldata stakingRewardInfos) external;

    /// @dev Used for validators to claim their staking rewards for validating the network
    /// @notice Rewards are incremented every epoch via syscall in `concludeEpoch()`
    function claimStakeRewards() external;

    /// @dev Returns previously staked funds and accrued rewards, if any, to the calling validator
    /// @notice May only be called after fully exiting
    /// @notice `StakeInfo::tokenId` will be set to `UNSTAKED` so the validator address cannot be reused
    function unstake() external;

    /// @dev Returns the current total supply of minted ConsensusNFTs
    function totalSupply() external view returns (uint256);

    /// @dev Fetches the claimable rewards accrued for a given validator address
    /// @notice Does not include the original stake amount and cannot be claimed until surpassing `minWithdrawAmount`
    /// @return claimableRewards The validator's claimable rewards, not including the validator's stake
    function getRewards(address ecdsaPubkey) external view returns (uint240 claimableRewards);

    /// @dev Returns staking information for the given address
    function stakeInfo(address ecdsaPubkey) external view returns (StakeInfo memory);

    /// @dev Returns the current stake version
    function stakeVersion() external view returns (uint8);

    /// @dev Returns the current stake amount
    function stakeAmount() external view returns (uint256);

    /// @dev Returns the current minimum withdrawal amount
    function minWithdrawAmount() external view returns (uint256);

    /// @dev Returns the current consensus block reward
    function consensusBlockReward() external view returns (uint256);

    /// @dev Permissioned function to upgrade stake, withdrawal, and consensus block reward configurations
    function upgradeStakeVersion(StakeConfig calldata newVersion) external returns (uint8);
}
