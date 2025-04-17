// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { StakeInfo, IStakeManager } from "./interfaces/IStakeManager.sol";
import { StakeManager } from "./StakeManager.sol";
import { IConsensusRegistry } from "./interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "./SystemCallable.sol";

//todo
import "forge-std/console2.sol";

/**
 * @title ConsensusRegistry
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract manages consensus validator external keys, staking, and committees
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
contract ConsensusRegistry is
    StakeManager,
    UUPSUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    SystemCallable,
    IConsensusRegistry
{
    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.ConsensusRegistry")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant ConsensusRegistryStorageSlot =
        0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100;

    /// @dev Signals a validator's pending status until activation/exit to correctly apply incentives
    uint32 internal constant PENDING_EPOCH = type(uint32).max;

    /**
     *
     *   consensus
     *
     */

    /// @inheritdoc IConsensusRegistry
    function concludeEpoch(address[] calldata newCommittee) external override onlySystemCall {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // update epoch and ring buffer info
        uint32 newEpoch = _updateEpochInfo($, newCommittee);
        
        // exit validators with `PendingExit` status if applicable
        ValidatorInfo[] memory pendingExit = _getValidators($, ValidatorStatus.PendingExit);
        for (uint256 i; i < pendingExit.length; ++i) {            
            // ensure validator is not in current or future committees
            uint256 index = $.tokenIdToIndex[pendingExit[i].tokenId];
            ValidatorInfo storage validator = $.validators[index];
            if (_exitEligibility($, validator)) {
                _exit(validator, newEpoch);
            }
        }

        // ensure new epoch's canonical network state is still BFT and of expected size
        uint256 numActiveValidators = _getValidators($, ValidatorStatus.Active).length;
        _checkFaultTolerance(numActiveValidators, newCommittee.length);
        // beyond BFT, the committee also must comprise all active validators if less than 10
        if (numActiveValidators <= 10) assert(numActiveValidators == newCommittee.length);

        emit NewEpoch(EpochInfo(newCommittee, uint64(block.number + 1)));
    }

    /// @inheritdoc IStakeManager
    function incrementRewards(StakeInfo[] calldata stakingRewardInfos) external override onlySystemCall {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint32 currentEpoch = $.currentEpoch;

        // update each validator's claimable rewards with given amounts
        for (uint256 i; i < stakingRewardInfos.length; ++i) {
            uint24 tokenId = stakingRewardInfos[i].tokenId;
            uint24 index = $.tokenIdToIndex[tokenId];
            ValidatorInfo storage currentValidator = $.validators[index];
            
            // ensure client provided rewards only to known validators that were active in previous epoch
            if (currentEpoch <= currentValidator.activationEpoch) {
                revert InvalidStatus(ValidatorStatus.PendingActivation);
            }
            // only genesis validators can be active with an `activationEpoch == 0`
            if (index > $.numGenesisValidators) {
                if (currentValidator.activationEpoch == 0) {
                    revert InvalidStatus(ValidatorStatus.Any);
                }
            }

            address validatorAddr = currentValidator.ecdsaPubkey;
            uint232 epochReward = stakingRewardInfos[i].stakingRewards;

            _stakeManagerStorage().stakeInfo[validatorAddr].stakingRewards += epochReward;
        }
    }

    /// @inheritdoc IConsensusRegistry
    function getCurrentEpoch() public view returns (uint32) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return $.currentEpoch;
    }

    /// @inheritdoc IConsensusRegistry
    function getEpochInfo(uint32 epoch) public view returns (EpochInfo memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint32 currentEpoch = $.currentEpoch;
        if (epoch > currentEpoch + 2 || (currentEpoch >= 3 && epoch < currentEpoch - 3)) {
            revert InvalidEpoch(epoch);
        }

        uint8 currentPointer = $.epochPointer;
        if (epoch > currentEpoch) {
            return _getFutureEpochInfo($, epoch, currentEpoch, currentPointer);
        } else {
            return _getRecentEpochInfo($, epoch, currentEpoch, currentPointer);
        }
    }

    /// @inheritdoc IConsensusRegistry
    function getValidators(ValidatorStatus status) public view returns (ValidatorInfo[] memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorIndex(address ecdsaPubkey) public view returns (uint24 validatorIndex) {
        validatorIndex = _getTokenId(_stakeManagerStorage(), ecdsaPubkey);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorByIndex(uint24 validatorIndex) public view returns (ValidatorInfo memory) {
        if (validatorIndex == 0) revert InvalidIndex(validatorIndex);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        return $.validators[uint256(validatorIndex)];
    }

    /**
     *
     *   validators
     *
     */

    /// @inheritdoc StakeManager
    function stake(
        bytes calldata blsPubkey
    )
        external
        payable
        override
        whenNotPaused
    {
        if (blsPubkey.length != 96) revert InvalidBLSPubkey();
        _checkStakeValue(msg.value);

        // require caller is known & whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        // enter validator in activation queue
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint24 validatorIndex = uint24($.validators.length);
        $.tokenIdToIndex[tokenId] = validatorIndex;
        _beginActivation($, msg.sender, blsPubkey, tokenId);
    }

    //todo stakeFor() ?

    /// @inheritdoc IConsensusRegistry
    function activate() external override whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        uint24 validatorIndex = $C.tokenIdToIndex[tokenId];
        // require caller status is `PendingActivation`
        _checkValidatorStatus($C, validatorIndex, ValidatorStatus.PendingActivation);

        // activate validator using next epoch for completeness wrt incentives
        ValidatorInfo storage callingValidator = $C.validators[validatorIndex];

        _activate(callingValidator, $C.currentEpoch);
    }

    /// @inheritdoc StakeManager
    function claimStakeRewards() external override whenNotPaused {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        _checkKnownValidator($, msg.sender);

        uint256 rewards = _claimStakeRewards($);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @inheritdoc IConsensusRegistry
    function beginExit() external whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint256 numActiveValidators = _getValidators($, ValidatorStatus.Active).length;
        uint256 committeeSize = $.epochInfo[$.epochPointer].committee.length;
        _checkFaultTolerance(numActiveValidators, committeeSize);

        // require caller status is `Active`
        uint24 validatorIndex = $.tokenIdToIndex[tokenId];
        _checkValidatorStatus($, validatorIndex, ValidatorStatus.Active);

        // enter validator in exit queue
        ValidatorInfo storage validator = $.validators[validatorIndex];
        _beginExit(validator);
    }

    /// @inheritdoc StakeManager
    function unstake() external override whenNotPaused {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, msg.sender);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        // require caller status is `Exited`
        uint24 validatorIndex = $C.tokenIdToIndex[tokenId];
        _checkValidatorStatus($C, validatorIndex, ValidatorStatus.Exited);

        // burn the ConsensusNFT, and permanently eject via `Any` and `UNSTAKED`
        _burn(validatorIndex);
        ValidatorInfo storage validator = $C.validators[validatorIndex];
        _retire(validator);

        // return stake and send any outstanding rewards
        uint256 stakeAndRewards = _unstake(validator.ecdsaPubkey);

        emit RewardsClaimed(msg.sender, stakeAndRewards);
    }

    /**
     *
     *   ERC721
     *
     */

    /// @inheritdoc StakeManager
    function mint(address ecdsaPubkey, uint256 tokenId) external override onlyOwner {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // validators may only possess one token which cannot be 0 or overflow
        if (balanceOf(ecdsaPubkey) != 0 || _getTokenId($, ecdsaPubkey) != 0) {
            revert AlreadyDefined(ecdsaPubkey);
        }
        if (tokenId == 0 || tokenId > type(uint24).max) revert InvalidTokenId(tokenId);

        // set tokenId (validator index is not known until stake time)
        $.stakeInfo[ecdsaPubkey].tokenId = uint24(tokenId);

        // issue a new ConsensusNFT
        _mint(ecdsaPubkey, tokenId);
    }

    /// @inheritdoc StakeManager
    function burn(address ecdsaPubkey) external override onlyOwner {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, msg.sender);

        // set recorded tokenId to `UNSTAKED` and burn the token
        $S.stakeInfo[ecdsaPubkey].tokenId = UNSTAKED;
        _burn(tokenId);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        uint256 validatorIndex = $C.tokenIdToIndex[tokenId];
        ValidatorInfo storage validator = $C.validators[validatorIndex];
        if (_exitEligibility($C, validator)) {
            // if validator is eligible, exit, unstake, and retire immediately
            _exit(validator, $C.currentEpoch);
            _unstake(ecdsaPubkey);
            _retire(validator);
        } else {
            revert CommitteeRequirement(ecdsaPubkey);
        }
    }

    /**
     *
     *   internals
     *
     */

    /// @notice Enters a validator into the activation queue upon receiving stake
    /// @dev Stores the new validator in the `validators` vector
    function _beginActivation(
        ConsensusRegistryStorage storage $,
        address ecdsaPubkey,
        bytes calldata blsPubkey,
        uint24 tokenId
    )
        internal
    {
        ValidatorInfo memory newValidator = ValidatorInfo(
            blsPubkey,
            ecdsaPubkey,
            PENDING_EPOCH,
            uint32(0),
            tokenId,
            ValidatorStatus.PendingActivation
        );
        $.validators.push(newValidator);

        emit ValidatorPendingActivation(newValidator);
    }

    /// @dev Activates a validator
    /// @dev Sets the next epoch as activation timestamp for epoch completeness wrt incentives
    function _activate(
        ValidatorInfo storage validator,
        uint32 currentEpoch
    )
        internal
    {
        validator.currentStatus = ValidatorStatus.Active;
        validator.activationEpoch = currentEpoch + 1;

        emit ValidatorActivated(validator);
    }

    /// @notice Enters a validator into the exit queue
    /// @dev Finalized by the protocol when the validator is no longer required for committees
    function _beginExit(
        ValidatorInfo storage validator
    )
        internal
    {
        // set validator status to `PendingExit` and set exit epoch
        validator.currentStatus = ValidatorStatus.PendingExit;
        validator.exitEpoch = PENDING_EPOCH;

        emit ValidatorPendingExit(validator);
    }

    function _exitEligibility(
        ConsensusRegistryStorage storage $,
        ValidatorInfo storage validator
    )
        internal
        view
        returns (bool)
    {
        // ensure validator is not in current or future committees
        address validatorAddr = validator.ecdsaPubkey;
        if (_isCurrentCommitteeMember($, validatorAddr) || _isFutureCommitteeMember($, validatorAddr)) {
            return false;
        } else {
            return true;
        }
    }

    /// @notice Exits a validator from the network, 
    /// @dev Only invoked via protocol client system call to `concludeEpoch()` or governance ejection
    /// @dev Once exited, the validator may unstake to reclaim their stake and rewards
    function _exit(
        ValidatorInfo storage validator,
        uint32 currentEpoch
    )
        internal
    {
        // set validator status to `Exited` and set exit epoch
        validator.currentStatus = ValidatorStatus.Exited;
        validator.exitEpoch = currentEpoch;

        emit ValidatorExited(validator);
    }

    /// @notice Permanently retires validator from the network by setting invalid status and index
    /// @dev Ensures an validator cannot rejoin after exiting + unstaking or after governance ejection
    /// @dev Rejoining must be done by restarting validator onboarding process
    function _retire(ValidatorInfo storage validator) internal {
        validator.currentStatus = ValidatorStatus.Any;
        validator.tokenId = UNSTAKED;
    }

    /// @dev Stores the number of blocks finalized in previous epoch and the voter committee for the new epoch
    function _updateEpochInfo(
        ConsensusRegistryStorage storage $,
        address[] memory newCommittee
    )
        internal
        returns (uint32)
    {
        // cache epoch ring buffer's pointers in memory
        uint8 prevEpochPointer = $.epochPointer;
        uint8 newEpochPointer = (prevEpochPointer + 1) % 4;

        // update new current epoch info
        address[] storage currentCommittee = $.futureEpochInfo[newEpochPointer].committee;
        $.epochInfo[newEpochPointer] = EpochInfo(currentCommittee, uint64(block.number));
        $.epochPointer = newEpochPointer;
        uint32 newEpoch = ++$.currentEpoch;

        // update future epoch info
        uint8 twoEpochsInFuturePointer = (newEpochPointer + 2) % 4;
        $.futureEpochInfo[twoEpochsInFuturePointer].committee = newCommittee;

        return (newEpoch);
    }

    /// @dev Fetch info for a future epoch; two epochs into future are stored
    /// @notice Block height is not known for future epochs, so it will be 0
    function _getFutureEpochInfo(ConsensusRegistryStorage storage $, uint32 futureEpoch, uint32 currentEpoch, uint8 currentPointer) internal view returns (EpochInfo memory) {
        uint8 futurePointer = (uint8(futureEpoch - currentEpoch) + currentPointer) % 4;
        return $.futureEpochInfo[futurePointer];
    }

    /// @dev Fetch info for a current or past epoch; four latest are stored (current and three in past)
    function _getRecentEpochInfo(ConsensusRegistryStorage storage $, uint32 recentEpoch, uint32 currentEpoch, uint8 currentPointer) internal view returns (EpochInfo memory) {
        // identify diff from pointer, preventing underflow by adding 4 (will be modulo'd away)
        uint8 pointerDiff = uint8(recentEpoch + 4 - currentEpoch);
        uint8 pointer = (currentPointer + pointerDiff) % 4;
        return $.epochInfo[pointer];
    }

    /// @dev Checks the given committee size against the total number of active validators using below 3f + 1 BFT rule
    /// @notice Prevents the network from reaching zero active validators (such as by exit)
    function _checkFaultTolerance(uint256 numActiveValidators, uint256 committeeSize) internal pure {
        if (numActiveValidators == 0) {
            revert InvalidCommitteeSize(0, 0);
        } else if (committeeSize > numActiveValidators) {
            // sanity check committee size is less than number of active validators
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        }

        // if the total validator set is small, all must vote and no faults can be tolerated
        if (numActiveValidators <= 4 && committeeSize != numActiveValidators) {
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        } else {
            // calculate number of tolerable faults for given node count using 33% threshold
            uint256 tolerableFaults = (numActiveValidators * 10_000) / 3;

            // committee size must be greater than tolerable faults
            uint256 minCommitteeSize = tolerableFaults / 10_000 + 1;
            if (committeeSize < minCommitteeSize) {
                revert InvalidCommitteeSize(minCommitteeSize, committeeSize);
            }
        }
    }

    /// @dev Reverts if the provided address doesn't correspond to an existing `tokenId`
    function _checkKnownValidator(
        StakeManagerStorage storage $,
        address ecdsaPubkey
    )
        private
        view
        returns (uint24)
    {
        uint24 tokenId = _getTokenId($, ecdsaPubkey);
        if (tokenId == 0 || balanceOf(ecdsaPubkey) != 1|| ownerOf(tokenId) != ecdsaPubkey) revert NotValidator(ecdsaPubkey);

        return tokenId;
    }

    /// @dev Reverts if the provided validator's status doesn't match the provided `requiredStatus`
    function _checkValidatorStatus(
        ConsensusRegistryStorage storage $,
        uint24 validatorIndex,
        ValidatorStatus requiredStatus
    )
        private
        view
    {
        ValidatorStatus status = $.validators[validatorIndex].currentStatus;
        if (status != requiredStatus) revert InvalidStatus(status);
    }

    /// @dev Checks that the given `ecdsaPubkey` is not a member of the next two committees
    function _isCommitteeMember(address ecdsaPubkey, address[] storage committee) internal view returns (bool) {
        // cache len to memory
        uint256 committeeLen = committee.length;
        for (uint256 i; i < committeeLen; ++i) {
            // terminate if `ecdsaPubkey` is a member of current committee
            if (committee[i] == ecdsaPubkey) return true;
        }

        return false;
    }

    /// @dev Returns true if the given `ecdsaPubkey` is on the current committee
    function _isCurrentCommitteeMember(ConsensusRegistryStorage storage $, address ecdsaPubkey) internal view returns (bool) {
        address[] storage currentCommittee = $.epochInfo[$.epochPointer].committee;
        return _isCommitteeMember(ecdsaPubkey, currentCommittee);
    }

    /// @dev Returns true if the given `ecdsaPubkey` is on either of the next two committees
    function _isFutureCommitteeMember(ConsensusRegistryStorage storage $, address ecdsaPubkey) internal view returns (bool) {
        uint8 currentEpochPointer = $.epochPointer;
        uint8 nextEpochPointer = (currentEpochPointer + 1) % 4;
        address[] storage nextCommittee = $.futureEpochInfo[nextEpochPointer].committee;
        if(_isCommitteeMember(ecdsaPubkey, nextCommittee)) return true;

        uint8 twoEpochsInFuturePointer = (currentEpochPointer + 2) % 4;
        address[] storage subsequentCommittee = $.futureEpochInfo[twoEpochsInFuturePointer].committee;
        if (_isCommitteeMember(ecdsaPubkey, subsequentCommittee)) return true;

        return false;
    }

    function _getValidators(
        ConsensusRegistryStorage storage $,
        ValidatorStatus status
    )
        internal
        view
        returns (ValidatorInfo[] memory)
    {
        ValidatorInfo[] memory allValidators = $.validators;

        if (status == ValidatorStatus.Any) {
            // provide Any status `== uint8(0)` to get full validator array (of any status)
            return allValidators;
        } else {
            // identify number of validators matching provided `status`
            uint256 numMatches;
            for (uint256 i; i < allValidators.length; ++i) {
                if (allValidators[i].currentStatus == status) ++numMatches;
            }

            // populate new array once length has been identified
            ValidatorInfo[] memory validatorsMatched = new ValidatorInfo[](numMatches);
            uint256 indexCounter;
            for (uint256 i; i < allValidators.length; ++i) {
                if (allValidators[i].currentStatus == status) {
                    validatorsMatched[indexCounter] = allValidators[i];
                    ++indexCounter;
                }
            }

            return validatorsMatched;
        }
    }

    function _getValidatorIndex(StakeManagerStorage storage $, address ecdsaPubkey) internal view returns (uint24) {
        uint24 tokenId = _checkKnownValidator($, ecdsaPubkey);
        return _consensusRegistryStorage().tokenIdToIndex[tokenId];
    }

    function _consensusRegistryStorage() internal pure returns (ConsensusRegistryStorage storage $) {
        assembly {
            $.slot := ConsensusRegistryStorageSlot
        }
    }

    /**
     *
     *   pausability
     *
     */

    /// @dev Emergency function to pause validator and stake management
    /// @notice Does not pause `concludeEpoch()`. Only accessible by `owner`
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Emergency function to unpause validator and stake management
    /// @notice Does not affect `concludeEpoch()`. Only accessible by `owner`
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     *
     *   upgradeability (devnet, testnet)
     *
     */

    /// @notice Not actually used since this contract is precompiled and written to TN at genesis
    /// It is left in the contract for readable information about the relevant storage slots at genesis
    /// @param initialValidators_ The initial validator set running Telcoin Network; these validators will
    /// comprise the voter committee for the first three epochs, ie `epochInfo[0:2]`
    function initialize(
        address rwTEL_,
        uint256 stakeAmount_,
        uint256 minWithdrawAmount_,
        ValidatorInfo[] memory initialValidators_,
        address owner_
    )
        external
        initializer
    {
        if (initialValidators_.length == 0 || initialValidators_.length > type(uint24).max) {
            revert InitializerArityMismatch();
        }

        __Ownable_init(owner_);
        __Pausable_init();

        StakeManagerStorage storage $S = _stakeManagerStorage();

        // Set stake storage configs
        $S.rwTEL = rwTEL_;
        $S.stakeAmount = stakeAmount_;
        $S.minWithdrawAmount = minWithdrawAmount_;

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        $C.numGenesisValidators = initialValidators_.length;

        // handle first iteration as a special case, performing an extra iteration to compensate
        for (uint256 i; i <= initialValidators_.length; ++i) {
            if (i == 0) {
                // push a null ValidatorInfo to the 0th index in `validators` as 0 should be an invalid `validatorIndex`
                $C.validators.push(
                    ValidatorInfo(
                        "", address(0x0), uint32(0), uint32(0), uint24(0), ValidatorStatus.Any
                    )
                );

                continue;
            }

            // execution only reaches this point once `i == 1`
            ValidatorInfo memory currentValidator = initialValidators_[i - 1];

            // assert `validatorIndex` struct members match expected value
            if (currentValidator.blsPubkey.length != 96) {
                revert InvalidBLSPubkey();
            }
            if (currentValidator.ecdsaPubkey == address(0x0)) {
                revert InvalidECDSAPubkey();
            }
            if (currentValidator.activationEpoch != uint32(0)) {
                revert InvalidEpoch(currentValidator.activationEpoch);
            }
            if (currentValidator.exitEpoch != uint32(0)) {
                revert InvalidEpoch(currentValidator.activationEpoch);
            }
            if (currentValidator.currentStatus != ValidatorStatus.Active) {
                revert InvalidStatus(currentValidator.currentStatus);
            }
            if (currentValidator.tokenId != i) {
                revert InvalidIndex(currentValidator.tokenId);
            }

            // first three epochs use initial validators as committee
            for (uint256 j; j <= 2; ++j) {
                $C.epochInfo[j].committee.push(currentValidator.ecdsaPubkey);
                $C.futureEpochInfo[j].committee.push(currentValidator.ecdsaPubkey);
            }

            uint256 tokenId = i;
            _stakeManagerStorage().stakeInfo[currentValidator.ecdsaPubkey].tokenId = uint24(tokenId);
            $C.validators.push(currentValidator);
            $C.tokenIdToIndex[uint24(tokenId)] = uint24(i);
            __ERC721_init("ConsensusNFT", "CNFT");
            _mint(currentValidator.ecdsaPubkey, tokenId);

            emit ValidatorActivated(currentValidator);
        }
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
