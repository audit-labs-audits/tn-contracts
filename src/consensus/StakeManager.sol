// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IRWTEL } from "../interfaces/IRWTEL.sol";

/**
 * @title StakeManager
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This abstract contract provides modular management of consensus validator stake
 * @dev Designed for inheritance by the ConsensusRegistry
 */
struct StakeInfo {
    uint16 validatorIndex;
    uint240 stakingRewards; // can be resized to uint104 (100bil $TEL)
}

abstract contract StakeManager {
    /// @custom:storage-location erc7201:telcoin.storage.StakeManager
    struct StakeManagerStorage {
        address rwTEL;
        uint256 stakeAmount;
        uint256 minWithdrawAmount;
        mapping(address => StakeInfo) stakeInfo;
    }

    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.StakeManager")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant StakeManagerStorageSlot =
        0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400;

    error InvalidStakeAmount(uint256 stakeAmount);
    error InsufficientRewards(uint256 withdrawAmount);

    /// @dev Fetches the claimable rewards accrued for a given validator address
    /// @notice Does not include the original stake amount and cannot be claimed until surpassing `minWithdrawAmount`
    /// @return claimableRewards The validator's claimable rewards, not including the validator's stake
    function getRewards(address ecdsaPubkey) public view virtual returns (uint240 claimableRewards);

    /// @dev Accepts the stake amount of native TEL and issues an activation request for the caller (validator)
    function stake(bytes calldata blsPubkey, bytes calldata blsSig, bytes32 ed25519Pubkey) external payable virtual;

    /// @dev Used for validators to claim their staking rewards for validating the network
    /// @notice Rewards are incremented every epoch via syscall in `finalizePreviousEpoch()`
    function claimStakeRewards() external virtual;

    /// @dev Returns previously staked funds and accrued rewards, if any, to the calling validator
    /// @notice May only be called after fully exiting
    function unstake() external virtual;

    /**
     *
     *   internals
     *
     */
    function _getRewards(
        StakeManagerStorage storage $,
        address ecdsaPubkey
    )
        internal
        view
        virtual
        returns (uint240 claimableRewards)
    {
        return $.stakeInfo[ecdsaPubkey].stakingRewards;
    }

    /// @notice Sends staking rewards only and is not used for withdrawing initial stake
    function _claimStakeRewards(StakeManagerStorage storage $) internal virtual returns (uint256 rewards) {
        rewards = _checkRewardsExceedMinWithdrawAmount($, msg.sender);

        // wipe ledger to prevent reentrancy and send via the `RWTEL` module
        $.stakeInfo[msg.sender].stakingRewards = 0;
        IRWTEL($.rwTEL).distributeStakeReward(msg.sender, rewards);
    }

    function _unstake() internal virtual returns (uint256 stakeAndRewards) {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // wipe ledger and send staked balance + rewards
        stakeAndRewards = $.stakeAmount + $.stakeInfo[msg.sender].stakingRewards;
        //todo: go through RWTEL module
        $.stakeInfo[msg.sender].stakingRewards = 0;
        (bool r,) = msg.sender.call{ value: stakeAndRewards }("");
        require(r);
    }

    function _checkRewardsExceedMinWithdrawAmount(
        StakeManagerStorage storage $,
        address caller
    )
        internal
        virtual
        returns (uint256 rewards)
    {
        rewards = $.stakeInfo[caller].stakingRewards;
        if (rewards < $.minWithdrawAmount) revert InsufficientRewards(rewards);
    }

    function _checkStakeValue(uint256 value) internal virtual {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        if (value != $.stakeAmount) revert InvalidStakeAmount(msg.value);
    }

    function _stakeManagerStorage() internal pure virtual returns (StakeManagerStorage storage $) {
        assembly {
            $.slot := StakeManagerStorageSlot
        }
    }
}
