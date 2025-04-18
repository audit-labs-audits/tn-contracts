// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { StakeInfo, IStakeManager } from "./interfaces/IStakeManager.sol";
import { StakeManager } from "./StakeManager.sol";
import { IConsensusRegistry } from "./interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "./SystemCallable.sol";

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
        _exitEligibleValidators($, pendingExit, newEpoch);

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
        //todo

        // update each validator's claimable rewards with given amounts
        for (uint256 i; i < stakingRewardInfos.length; ++i) {
            ValidatorInfo memory currentValidator = getValidatorByTokenId(stakingRewardInfos[i].tokenId);
            uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), currentValidator.ecdsaPubkey);
            assert(tokenId == stakingRewardInfos[i].tokenId);

            // ensure client provided rewards only to known validators that were active in previous epoch
            if (currentEpoch < currentValidator.activationEpoch) {
                revert InvalidStatus(ValidatorStatus.PendingActivation);
            }

            //todo: is this check necessary? abstraction?
            // only genesis validators can be active with an `activationEpoch == 0`
            if (i > $.numGenesisValidators) {
                //todo: check if genesis validators have left and been reminted
                if (currentValidator.activationEpoch == 0) {
                    revert InvalidStatus(ValidatorStatus.Any);
                }
            }

            uint232 epochReward = stakingRewardInfos[i].stakingRewards;

            _stakeManagerStorage().stakeInfo[currentValidator.ecdsaPubkey].stakingRewards += epochReward;
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
    function getValidatorTokenId(address ecdsaPubkey) public view returns (uint256) {
        return _checkKnownValidator(_stakeManagerStorage(), ecdsaPubkey);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorByTokenId(uint256 tokenId) public view returns (ValidatorInfo memory) {
        if (tokenId >= UNSTAKED || !_exists(tokenId)) revert InvalidTokenId(tokenId);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        return $.validators[uint24(tokenId)];
    }

    /**
     *
     *   validators
     *
     */

    /// @inheritdoc StakeManager
    function stake(bytes calldata blsPubkey) external payable override whenNotPaused {
        if (blsPubkey.length != 96) revert InvalidBLSPubkey();
        _checkStakeValue(msg.value);

        // require caller is known & whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        // enter validator in activation queue
        _beginActivation(_consensusRegistryStorage(), msg.sender, blsPubkey, tokenId);
    }

    //todo stakeFor() ?

    /// @inheritdoc IConsensusRegistry
    function activate() external override whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        // require caller status is `PendingActivation`
        _checkValidatorStatus($C, tokenId, ValidatorStatus.PendingActivation);

        ValidatorInfo storage validator = $C.validators[tokenId];
        // activate validator using subsequent epoch for future committee size calculations
        _activate(validator, $C.currentEpoch);
    }

    /// @inheritdoc StakeManager
    function claimStakeRewards() external override whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        StakeManagerStorage storage $ = _stakeManagerStorage();
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

        // require caller status is `Active` and `currentEpoch >= activationEpoch`
        _checkValidatorStatus($, tokenId, ValidatorStatus.Active);
        ValidatorInfo storage validator = $.validators[tokenId];
        uint32 currentEpoch = $.currentEpoch;
        if (currentEpoch < $.validators[tokenId].activationEpoch) {
            revert InvalidEpoch(currentEpoch);
        }

        // enter validator in exit queue
        _beginExit(validator);
    }

    /// @inheritdoc StakeManager
    function unstake() external override whenNotPaused {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, msg.sender);

        // require caller status is `Exited`
        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        _checkValidatorStatus($C, tokenId, ValidatorStatus.Exited);

        // burn the ConsensusNFT and permanently retire the validator
        ValidatorInfo storage validator = $C.validators[tokenId];
        _retire(validator);

        // return stake and send any outstanding rewards
        uint256 stakeAndRewards = _unstake(validator.ecdsaPubkey, uint256(tokenId));

        emit RewardsClaimed(msg.sender, stakeAndRewards);
    }

    /**
     *
     *   ERC721
     *
     */

    /// @inheritdoc StakeManager
    function mint(address ecdsaPubkey, uint256 tokenId) external override onlyOwner {
        // tokenId cannot be in use, `0`, `UNSTAKED`, or out of uint24 bounds
        if (tokenId >= UNSTAKED || _exists(tokenId)) revert InvalidTokenId(tokenId);

        StakeManagerStorage storage $ = _stakeManagerStorage();
        // validators may only possess one token and `ecdsaPubkey` cannot be reused
        if (balanceOf(ecdsaPubkey) != 0 || _getTokenId($, ecdsaPubkey) != 0) {
            revert AlreadyDefined(ecdsaPubkey);
        }

        // set tokenId and increment supply
        $.stakeInfo[ecdsaPubkey].tokenId = uint24(tokenId);
        $.totalSupply++;

        // issue the ConsensusNFT
        _mint(ecdsaPubkey, tokenId);
    }

    /// @inheritdoc StakeManager
    function burn(address ecdsaPubkey) external override onlyOwner returns (bool) {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, ecdsaPubkey);

        // set recorded tokenId to `UNSTAKED`, decrement supply, and burn the token
        $S.stakeInfo[ecdsaPubkey].tokenId = UNSTAKED;
        $S.totalSupply--;
        _burn(tokenId);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        ValidatorInfo storage validator = $C.validators[tokenId];
        bool ejected = _ejectFromCommittees($C, ecdsaPubkey);

        // exit, unstake, and retire validator immediately
        _exit(validator, $C.currentEpoch);
        _unstake(ecdsaPubkey, tokenId);
        _retire(validator);

        return ejected;
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
        ValidatorInfo memory newValidator =
            ValidatorInfo(blsPubkey, ecdsaPubkey, PENDING_EPOCH, uint32(0), tokenId, ValidatorStatus.PendingActivation);
        $.validators[tokenId] = newValidator;

        emit ValidatorPendingActivation(newValidator);
    }

    /// @dev Activates a validator
    /// @dev Sets the next epoch as activation timestamp for epoch completeness wrt incentives
    function _activate(ValidatorInfo storage validator, uint32 currentEpoch) internal {
        validator.currentStatus = ValidatorStatus.Active;
        validator.activationEpoch = currentEpoch + 2;

        emit ValidatorActivated(validator);
    }

    /// @notice Enters a validator into the exit queue
    /// @dev Finalized by the protocol when the validator is no longer required for committees
    function _beginExit(ValidatorInfo storage validator) internal {
        // set validator status to `PendingExit` and set exit epoch
        validator.currentStatus = ValidatorStatus.PendingExit;
        validator.exitEpoch = PENDING_EPOCH;

        emit ValidatorPendingExit(validator);
    }

    /// @notice Exits a validator from the network,
    /// @dev Only invoked via protocol client system call to `concludeEpoch()` or governance ejection
    /// @dev Once exited, the validator may unstake to reclaim their stake and rewards
    function _exit(ValidatorInfo storage validator, uint32 currentEpoch) internal {
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

        emit ValidatorRetired(validator);
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

    /// @notice Finalizes exit for validators with `PendingExit` status if applicable
    /// @dev Protocol determines a validator is eligible if not in committee across 3 epochs
    /// @dev Invoked via system call within `concludeEpoch()`
    function _exitEligibleValidators(
        ConsensusRegistryStorage storage $,
        ValidatorInfo[] memory pendingExit,
        uint32 currentEpoch
    )
        internal
    {
        for (uint256 i; i < pendingExit.length; ++i) {
            // ensure validator is not in current or future committees
            uint24 tokenId = pendingExit[i].tokenId;
            ValidatorInfo storage validator = $.validators[tokenId];
            if (_exitEligibility($, validator)) {
                _exit(validator, currentEpoch);
            }
        }
    }

    /// @notice Forcibly eject a validator from the current, next, and subsequent committees
    /// @dev Intended for sparing use; bypasses BFT or committee size checks
    function _ejectFromCommittees(ConsensusRegistryStorage storage $, address ecdsaPubkey) internal returns (bool) {
        bool ejected;

        uint8 currentEpochPointer = $.epochPointer;
        address[] storage currentCommittee = $.epochInfo[currentEpochPointer].committee;
        uint256 len = currentCommittee.length; // cache in memory
        for (uint256 i; i < len; ++i) {
            if (currentCommittee[i] == ecdsaPubkey) {
                currentCommittee[i] = currentCommittee[len - 1];
                currentCommittee.pop();
                ejected = true;
            }
        }

        address[] storage nextCommittee = $.futureEpochInfo[(currentEpochPointer + 1) % 4].committee;
        len = nextCommittee.length;
        for (uint256 i; i < len; ++i) {
            if (nextCommittee[i] == ecdsaPubkey) {
                nextCommittee[i] = nextCommittee[len - 1];
                nextCommittee.pop();
                ejected = true;
            }
        }

        address[] storage subsequentCommittee = $.futureEpochInfo[(currentEpochPointer + 2) % 4].committee;
        len = subsequentCommittee.length;
        for (uint256 i; i < len; ++i) {
            if (subsequentCommittee[i] == ecdsaPubkey) {
                subsequentCommittee[i] = subsequentCommittee[len - 1];
                subsequentCommittee.pop();
                ejected = true;
            }
        }

        return ejected;
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
    function _getFutureEpochInfo(
        ConsensusRegistryStorage storage $,
        uint32 futureEpoch,
        uint32 currentEpoch,
        uint8 currentPointer
    )
        internal
        view
        returns (EpochInfo memory)
    {
        uint8 futurePointer = (uint8(futureEpoch - currentEpoch) + currentPointer) % 4;
        return $.futureEpochInfo[futurePointer];
    }

    /// @dev Fetch info for a current or past epoch; four latest are stored (current and three in past)
    function _getRecentEpochInfo(
        ConsensusRegistryStorage storage $,
        uint32 recentEpoch,
        uint32 currentEpoch,
        uint8 currentPointer
    )
        internal
        view
        returns (EpochInfo memory)
    {
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
    function _checkKnownValidator(StakeManagerStorage storage $, address ecdsaPubkey) private view returns (uint24) {
        uint24 tokenId = _getTokenId($, ecdsaPubkey);
        if (tokenId == 0 || tokenId == UNSTAKED) revert InvalidTokenId(tokenId);
        if (ownerOf(tokenId) != ecdsaPubkey) revert NotValidator(ecdsaPubkey);

        return tokenId;
    }

    /// @dev Reverts if the provided validator's status doesn't match the provided `requiredStatus`
    function _checkValidatorStatus(
        ConsensusRegistryStorage storage $,
        uint24 tokenId,
        ValidatorStatus requiredStatus
    )
        private
        view
    {
        ValidatorStatus status = $.validators[tokenId].currentStatus;
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
    function _isCurrentCommitteeMember(
        ConsensusRegistryStorage storage $,
        address ecdsaPubkey
    )
        internal
        view
        returns (bool)
    {
        address[] storage currentCommittee = $.epochInfo[$.epochPointer].committee;
        return _isCommitteeMember(ecdsaPubkey, currentCommittee);
    }

    /// @dev Returns true if the given `ecdsaPubkey` is on either of the next two committees
    function _isFutureCommitteeMember(
        ConsensusRegistryStorage storage $,
        address ecdsaPubkey
    )
        internal
        view
        returns (bool)
    {
        uint8 currentEpochPointer = $.epochPointer;
        uint8 nextEpochPointer = (currentEpochPointer + 1) % 4;
        address[] storage nextCommittee = $.futureEpochInfo[nextEpochPointer].committee;
        if (_isCommitteeMember(ecdsaPubkey, nextCommittee)) return true;

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
        ValidatorInfo[] memory allValidators = new ValidatorInfo[](_stakeManagerStorage().totalSupply);
        for (uint256 i; i < allValidators.length; ++i) {
            allValidators[i] = $.validators[uint24(i + 1)];
        }

        if (status == ValidatorStatus.Any) {
            // provide Any status `== uint8(0)` to get full validator list
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
        $C.numGenesisValidators = uint8(initialValidators_.length);

        // set 0th validator placeholder with invalid values for future checks
        $C.validators[0] =
            ValidatorInfo(hex"ff", address(0xff), uint32(0xff), uint32(0xff), uint24(0xff), ValidatorStatus.Any);
        for (uint256 i; i < initialValidators_.length; ++i) {
            ValidatorInfo memory currentValidator = initialValidators_[i];

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
            uint24 tokenId = uint24(i + 1);
            if (currentValidator.tokenId != tokenId) {
                revert InvalidTokenId(currentValidator.tokenId);
            }

            // first three epochs use initial validators as committee
            for (uint256 j; j <= 2; ++j) {
                $C.epochInfo[j].committee.push(currentValidator.ecdsaPubkey);
                $C.futureEpochInfo[j].committee.push(currentValidator.ecdsaPubkey);
            }

            $C.validators[tokenId] = currentValidator;
            $S.stakeInfo[currentValidator.ecdsaPubkey].tokenId = tokenId;
            $S.totalSupply++;
            __ERC721_init("ConsensusNFT", "CNFT");
            _mint(currentValidator.ecdsaPubkey, tokenId);

            emit ValidatorActivated(currentValidator);
        }
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
