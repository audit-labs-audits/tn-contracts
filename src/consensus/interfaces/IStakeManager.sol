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
        mapping(address => Delegation) delegations;
    }

    struct StakeConfig {
        uint256 stakeAmount;
        uint256 minWithdrawAmount;
        uint256 consensusBlockReward;
    }

    struct Delegation {
        bytes32 blsPubkeyHash;
        address delegator;
        uint24 tokenId;
        uint8 validatorVersion;
        uint64 nonce;
    }

    error InvalidTokenId(uint256 tokenId);
    error InvalidStakeAmount(uint256 stakeAmount);
    error InsufficientRewards(uint256 withdrawAmount);
    error NotDelegator(address notDelegator);
    error NotTransferable();
    error RequiresConsensusNFT();

    /// @dev Accepts the native TEL stake amount from the calling validator, enabling later self-activation
    /// @notice Caller must already have been issued a `ConsensusNFT` by Telcoin governance
    function stake(bytes calldata blsPubkey) external payable;

    /// @dev Accepts delegated stake from a non-validator caller authorized by a validator's EIP712 signature
    /// @notice `ecdsaPubkey` must be a validator already in possession of a `ConsensusNFT`
    function delegateStake(
        bytes calldata blsPubkey,
        address ecdsaPubkey,
        bytes calldata validatorSig
    )
        external
        payable;

    /// @dev The network's primary rewards distribution method
    /// @notice May only be called by the client via system call, at the end of each epoch
    function incrementRewards(StakeInfo[] calldata stakingRewardInfos) external;

    /// @dev Used by rewardees to claim staking rewards
    function claimStakeRewards(address ecdaPubkey) external;

    /// @dev Returns previously staked funds in addition to accrued rewards, if any, to the staker
    /// @notice May only be called after fully exiting
    /// @notice `StakeInfo::tokenId` will be set to `UNSTAKED` so the validator address cannot be reused
    function unstake(address ecdsaPubkey) external;

    /// @dev Returns the current total supply of minted ConsensusNFTs
    function totalSupply() external view returns (uint256);

    /// @dev Fetches the claimable rewards accrued for a given validator address
    /// @return _ The validator's claimable rewards, not including the validator's stake
    function getRewards(address ecdsaPubkey) external view returns (uint240);

    /// @dev Returns staking information for the given address
    function stakeInfo(address ecdsaPubkey) external view returns (StakeInfo memory);

    /// @dev Returns the current stake version
    function stakeVersion() external view returns (uint8);

    /// @dev Returns the current stake configuration
    function stakeConfig(uint8 version) external view returns (StakeConfig memory);

    /// @dev Permissioned function to upgrade stake, withdrawal, and consensus block reward configurations
    function upgradeStakeVersion(StakeConfig calldata newVersion) external returns (uint8);
}
