// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IRWTEL } from "../interfaces/IRWTEL.sol";
import { IStakeManager } from "./interfaces/IStakeManager.sol";

/**
 * @title StakeManager
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This abstract contract provides modular management of consensus validator stake
 * @dev Designed for inheritance by the ConsensusRegistry
 */
abstract contract StakeManager is ERC721Upgradeable, IStakeManager {
    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.StakeManager")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant StakeManagerStorageSlot =
        0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400;

    /// @inheritdoc IStakeManager
    function stake(bytes calldata blsPubkey, bytes calldata blsSig, bytes32 ed25519Pubkey) external payable virtual;

    /// @inheritdoc IStakeManager
    function claimStakeRewards() external virtual;

    /// @inheritdoc IStakeManager
    function unstake() external virtual;

    /// @inheritdoc IStakeManager
    function getRewards(address ecdsaPubkey) public view virtual returns (uint240 claimableRewards) {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        claimableRewards = _getRewards($, ecdsaPubkey);
    }

    /// @notice Consensus NFTs are soulbound to validators that mint them and cannot be transfered
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        revert NotTransferable();
    }

    /// @notice Consensus NFTs are soulbound to validators that mint them and cannot be transfered
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        revert NotTransferable();
    }

    /**
     *
     *   internals
     *
     */

    /// @notice Sends staking rewards only and is not used for withdrawing initial stake
    function _claimStakeRewards(StakeManagerStorage storage $) internal virtual returns (uint256 rewards) {
        rewards = _checkRewardsExceedMinWithdrawAmount($, msg.sender);

        // wipe ledger to prevent reentrancy and send via the `RWTEL` module
        $.stakeInfo[msg.sender].stakingRewards = 0;
        IRWTEL($.rwTEL).distributeStakeReward(msg.sender, rewards);
    }

    function _unstake() internal virtual returns (uint256 stakeAndRewards) {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // wipe ledger and send rewards, then send stake
        uint256 rewards = uint256($.stakeInfo[msg.sender].stakingRewards);
        $.stakeInfo[msg.sender].stakingRewards = 0;
        IRWTEL($.rwTEL).distributeStakeReward(msg.sender, rewards);

        uint256 stakeAmount = $.stakeAmount;
        (bool r,) = msg.sender.call{ value: stakeAmount }("");
        require(r);

        return stakeAmount + rewards;
    }

    /// @notice Reverts if `validatorIndex` is not already minted as a `tokenId`
    /// as well as if the returned owner does not match the given `caller` address
    function _checkConsensusNFTOwnership(address caller, uint256 validatorIndex) internal virtual {
        // `ERC721Upgradeable::ownerOf()` will revert if the given index is not an existing `tokenId`
        if (ownerOf(validatorIndex) != caller) revert RequiresConsensusNFT();
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

    function _stakeManagerStorage() internal pure virtual returns (StakeManagerStorage storage $) {
        assembly {
            $.slot := StakeManagerStorageSlot
        }
    }
}
