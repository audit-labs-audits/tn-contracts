// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IRWTEL } from "../interfaces/IRWTEL.sol";
import { StakeInfo, IStakeManager } from "./interfaces/IStakeManager.sol";

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

    /// @dev Validators that unstake are permanently ejected by setting their index to `UNSTAKED`
    /// @notice Rejoining requires re-onboarding with new validator address, tokenId, stake, & index
    uint24 internal constant UNSTAKED = type(uint24).max;

    /// @inheritdoc IStakeManager
    function stake(bytes calldata blsPubkey) external payable virtual;

    /// @inheritdoc IStakeManager
    function incrementRewards(StakeInfo[] calldata stakingRewardInfos) external virtual;

    /// @inheritdoc IStakeManager
    function claimStakeRewards() external virtual;

    /// @inheritdoc IStakeManager
    function unstake() external virtual;

    /// @inheritdoc IStakeManager
    function getRewards(address ecdsaPubkey) public view virtual returns (uint240 claimableRewards) {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        claimableRewards = _getRewards($, ecdsaPubkey);
    }

    /**
     *
     *   ERC721
     *
     */

    /// @dev The StakeManager's ERC721 ledger serves a permissioning role over validators, requiring
    /// Telcoin governance to approve each node operator and manually issue them a `ConsensusNFT`
    /// @param to Refers to the struct member `ValidatorInfo.ecdsaPubkey` in `IConsensusRegistry`
    /// @param tokenId Refers to the `ERC721::tokenId` which must be less than `UNSTAKED` and nonzero
    /// For storage efficiency, tokenIds can be reused after being burned though ecdsaPubkeys cannot
    /// @notice Access-gated in ConsensusRegistry to its owner, which is a Telcoin governance address
    function mint(address to, uint256 tokenId) external virtual;

    /// @dev In the case of malicious or erroneous node operator behavior, governance can use this function 
    /// to burn a validator's `ConsensusNFT` and immediately eject from consensus committees if applicable
    /// @param from Refers to the struct member `ValidatorInfo.ecdsaPubkey` in `IConsensusRegistry`
    /// @notice ECDSA pubkey `from` will be marked `UNSTAKED` so the validator address cannot be reused
    /// @notice Access-gated in ConsensusRegistry to its owner, which is a Telcoin governance address
    function burn(address from) external virtual returns (bool);

    /// @notice Consensus NFTs are soulbound to validators that mint them and cannot be transfered
    function transferFrom(
        address,
        /* from */
        address,
        /* to */
        uint256 /* tokenId */
    )
        public
        virtual
        override
    {
        revert NotTransferable();
    }

    /// @notice Consensus NFTs are soulbound to validators that mint them and cannot be transfered
    function safeTransferFrom(
        address, /* from */
        address, /* to */
        uint256, /* tokenId */
        bytes memory /* data */
    )
        public
        virtual
        override
    {
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

    //todo: handle validatorAddr, 
    function _unstake(address validatorAddr, uint256 tokenId) internal virtual returns (uint256 stakeAndRewards) {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // wipe existing stakeInfo and burn the token
        StakeInfo storage stakeInfo = $.stakeInfo[msg.sender];
        uint256 rewards = uint256(stakeInfo.stakingRewards);
        stakeInfo.stakingRewards = 0;
        stakeInfo.tokenId = UNSTAKED;
        $.totalSupply--;
        _burn(tokenId);

        // forward the stake amount and outstanding rewards through RWTEL module to caller
        uint256 stakeAmount = $.stakeAmount; //todo handle configurable stake amt
        IRWTEL($.rwTEL).distributeStakeReward{ value: stakeAmount }(msg.sender, rewards);

        return stakeAmount + rewards;
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

    function _getTokenId(StakeManagerStorage storage $, address ecdsaPubkey) internal view returns (uint24) {
        uint24 tokenId = $.stakeInfo[ecdsaPubkey].tokenId;
        if (tokenId == 0) revert ERC721NonexistentToken(uint256(tokenId));

        return tokenId;
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        if (tokenId == 0) revert ERC721NonexistentToken(tokenId);
        return _ownerOf(tokenId) != address(0);
    }

    function _stakeManagerStorage() internal pure virtual returns (StakeManagerStorage storage $) {
        assembly {
            $.slot := StakeManagerStorageSlot
        }
    }
}
