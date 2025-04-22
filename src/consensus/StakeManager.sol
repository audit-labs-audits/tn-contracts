// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { EIP712 } from "solady/utils/EIP712.sol";
import { IRWTEL } from "../interfaces/IRWTEL.sol";
import { IncentiveInfo, IStakeManager } from "./interfaces/IStakeManager.sol";

/**
 * @title StakeManager
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This abstract contract provides modular management of consensus validator stake
 * @dev Designed for inheritance by the ConsensusRegistry
 */
abstract contract StakeManager is ERC721Upgradeable, EIP712, IStakeManager {
    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.StakeManager")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant StakeManagerStorageSlot =
        0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400;

    /// @dev Validators that unstake are permanently ejected by setting their index to `UNSTAKED`
    /// @notice Rejoining requires re-onboarding with new validator address, tokenId, stake, & index
    uint24 internal constant UNSTAKED = type(uint24).max;

    /// @dev EIP-712 typed struct hash used to enable delegated proof of stake
    bytes32 DELEGATION_TYPEHASH = keccak256(
        "Delegation(bytes32 blsPubkeyHash,address delegator,uint24 tokenId,uint8 validatorVersion,uint64 nonce)"
    );

    /// @inheritdoc IStakeManager
    function stake(bytes calldata blsPubkey) external payable virtual;

    /// @inheritdoc IStakeManager
    function delegateStake(
        bytes calldata blsPubkey,
        address ecdsaPubkey,
        bytes calldata validatorSig
    )
        external
        payable
        virtual;

    /// @inheritdoc IStakeManager
    function applyIncentives(IncentiveInfo[] calldata incentives) external virtual;

    /// @inheritdoc IStakeManager
    function claimStakeRewards(address ecsdaPubkey) external virtual;

    /// @inheritdoc IStakeManager
    function unstake(address ecdsaPubkey) external virtual;

    /// @inheritdoc IStakeManager
    function getRewards(address ecdsaPubkey) public view virtual returns (uint240) {
        return _getRewards(_stakeManagerStorage(), ecdsaPubkey);
    }

    /// @inheritdoc IStakeManager
    function incentiveInfo(address ecdsaPubkey) public view virtual returns (IncentiveInfo memory) {
        return _stakeManagerStorage().incentiveInfo[ecdsaPubkey];
    }

    /// @inheritdoc IStakeManager
    function stakeVersion() public view virtual returns (uint8) {
        return _stakeManagerStorage().stakeVersion;
    }

    /// @inheritdoc IStakeManager
    function stakeConfig(uint8 version) public view virtual returns (StakeConfig memory) {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        return $.versions[version];
    }

    /// @inheritdoc IStakeManager
    function upgradeStakeVersion(StakeConfig calldata config) external virtual returns (uint8);

    /**
     *
     *   ERC721
     *
     */

    /// @dev The StakeManager's ERC721 ledger serves a permissioning role over validators, requiring
    /// Telcoin governance to approve each node operator and manually issue them a `ConsensusNFT`
    /// @param to Refers to the struct member `ValidatorInfo.ecdsaPubkey` in `IConsensusRegistry`
    /// @param tokenId Refers to the `ERC721::tokenId` which must be less than `UNSTAKED` and nonzero
    /// tokenIds must be minted in order unless overwriting a retired validator for storage efficiency
    /// @notice Access-gated in ConsensusRegistry to its owner, which is a Telcoin governance address
    function mint(address to, uint256 tokenId) external virtual;

    /// @dev In the case of malicious or erroneous node operator behavior, governance can use this function
    /// to burn a validator's `ConsensusNFT` and immediately eject from consensus committees if applicable
    /// @param from Refers to the struct member `ValidatorInfo.ecdsaPubkey` in `IConsensusRegistry`
    /// @notice ECDSA pubkey `from` will be marked `UNSTAKED` so the validator address cannot be reused
    /// @dev Intended for sparing use; only reverts if burning results in empty committee
    function burn(address from) external virtual;

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

    /// @inheritdoc IStakeManager
    function totalSupply() public view virtual returns (uint256) {
        return _stakeManagerStorage().totalSupply;
    }

    /**
     *
     *   internals
     *
     */
    function _claimStakeRewards(
        StakeManagerStorage storage $,
        address ecdsaPubkey,
        address recipient,
        uint8 validatorVersion
    )
        internal
        virtual
        returns (uint256 rewards)
    {
        rewards = _checkRewardsExceedMinWithdrawAmount($, ecdsaPubkey, validatorVersion);
        // wipe ledger to prevent reentrancy and send via the `RWTEL` module
        $.incentiveInfo[ecdsaPubkey].stakingRewards = 0;
        IRWTEL($.rwTEL).distributeStakeReward(recipient, rewards);
    }

    function _unstake(
        address ecdsaPubkey,
        address recipient,
        uint256 tokenId,
        uint8 validatorVersion
    )
        internal
        virtual
        returns (uint256 stakeAndRewards)
    {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // wipe existing incentiveInfo and burn the token
        IncentiveInfo storage info = $.incentiveInfo[ecdsaPubkey];
        uint256 rewards = uint256(info.stakingRewards);
        info.stakingRewards = 0;
        info.tokenId = UNSTAKED;
        $.totalSupply--;
        _burn(tokenId);

        // forward the stake amount and outstanding rewards through RWTEL module to caller
        uint256 stakeAmt = $.versions[validatorVersion].stakeAmount;
        IRWTEL($.rwTEL).distributeStakeReward{ value: stakeAmt }(recipient, rewards);

        return stakeAmt + rewards;
    }

    function _checkRewardsExceedMinWithdrawAmount(
        StakeManagerStorage storage $,
        address ecdsaPubkey,
        uint8 validatorVersion
    )
        internal
        virtual
        returns (uint256 rewards)
    {
        rewards = incentiveInfo(ecdsaPubkey).stakingRewards;
        if (rewards < $.versions[validatorVersion].minWithdrawAmount) revert InsufficientRewards(rewards);
    }

    function _checkStakeValue(uint256 value, uint8 version) internal virtual {
        if (value != _stakeManagerStorage().versions[version].stakeAmount) revert InvalidStakeAmount(msg.value);
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
        return $.incentiveInfo[ecdsaPubkey].stakingRewards;
    }

    function _getTokenId(StakeManagerStorage storage $, address ecdsaPubkey) internal view returns (uint24) {
        return $.incentiveInfo[ecdsaPubkey].tokenId;
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        if (tokenId == 0 || tokenId >= UNSTAKED) revert InvalidTokenId(tokenId);
        return _ownerOf(tokenId) != address(0);
    }

    function _stakeManagerStorage() internal pure virtual returns (StakeManagerStorage storage $) {
        assembly {
            $.slot := StakeManagerStorageSlot
        }
    }

    function _domainNameAndVersion()
        internal
        view
        virtual
        override
        returns (string memory name, string memory version)
    {
        return ("Telcoin StakeManager", "1");
    }
}
