// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import { IRWTEL } from "../interfaces/IRWTEL.sol";
import { StakeInfo, StakeManager } from "./StakeManager.sol";
import { IConsensusRegistry } from "./IConsensusRegistry.sol";
import { SystemCallable } from "./SystemCallable.sol";

/**
 * @title ConsensusRegistry
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract manages consensus validator external keys, staking, and committees
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
contract ConsensusRegistry is StakeManager, UUPSUpgradeable, PausableUpgradeable, OwnableUpgradeable, SystemCallable, IConsensusRegistry {
    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.ConsensusRegistry")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant ConsensusRegistryStorageSlot =
        0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100;

    /**
     *
     *   consensus
     *
     */

    /// @inheritdoc IConsensusRegistry
    function finalizePreviousEpoch(
        uint64 numBlocks,
        uint16[] calldata newCommitteeIndices,
        StakeInfo[] calldata stakingRewardInfos
    )
        external onlySystemCall
        returns (uint32 newEpoch, uint64 newBlockHeight, uint256 numActiveValidators)
    {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // update epoch and ring buffer info
        (newEpoch, newBlockHeight) = _updateEpochInfo($, newCommitteeIndices, numBlocks);
        // update full validator set by activating/ejecting pending validators
        numActiveValidators = _updateValidatorSet($, newEpoch);

        // ensure new epoch's canonical network state is still BFT
        _checkFaultTolerance(numActiveValidators, newCommitteeIndices.length);

        // update each validator's claimable rewards with given amounts
        _incrementRewards($, stakingRewardInfos, newEpoch);

        emit NewEpoch(EpochInfo(newCommitteeIndices, newBlockHeight));
    }

    /// @inheritdoc IConsensusRegistry
    function getCurrentEpoch() public view returns (uint32) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return $.currentEpoch;
    }

    /// @inheritdoc IConsensusRegistry
    function getEpochInfo(uint32 epoch) public view returns (EpochInfo memory currentEpochInfo) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        if (epoch >= 4 && epoch < $.currentEpoch - 4) revert InvalidEpoch(epoch);

        uint8 pointer = $.epochPointer;
        currentEpochInfo = $.epochInfo[pointer];
    }

    /// @inheritdoc IConsensusRegistry
    function getValidators(ValidatorStatus status) public view returns (ValidatorInfo[] memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorIndex(address ecdsaPubkey) public view returns (uint16 validatorIndex) {
        validatorIndex = _getValidatorIndex(_stakeManagerStorage(), ecdsaPubkey);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorByIndex(uint16 validatorIndex) public view returns (ValidatorInfo memory validator) {
        if (validatorIndex == 0) revert InvalidIndex(validatorIndex);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        validator = $.validators[uint256(validatorIndex)];
    }

    /**
     *
     *   staking
     *
     */

    /// @inheritdoc StakeManager
    function stake(
        bytes calldata blsPubkey,
        bytes calldata blsSig,
        bytes32 ed25519Pubkey
    )
        external
        payable
        override
        whenNotPaused
    {
        if (blsPubkey.length != 48) revert InvalidBLSPubkey();
        if (blsSig.length != 96) revert InvalidProof();
        _checkStakeValue(msg.value);

        // require caller is a verified protocol validator - how to do this? : must possess a consensus NFT
        // how to prove ownership of blsPubkey using blsSig - offchain?

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        uint32 activationEpoch = $.currentEpoch + 2;
        uint16 validatorIndex = _getValidatorIndex(_stakeManagerStorage(), msg.sender);
        if (validatorIndex == 0) {
            // caller is a new validator; update its index in `StakeManager` storage
            validatorIndex = uint16($.validators.length);
            _stakeManagerStorage().stakeInfo[msg.sender].validatorIndex = validatorIndex;

            // push new validator to `validators` array
            ValidatorInfo memory newValidator = ValidatorInfo(
                blsPubkey,
                ed25519Pubkey,
                msg.sender,
                activationEpoch,
                uint32(0),
                validatorIndex,
                bytes4(0),
                ValidatorStatus.PendingActivation
            );
            $.validators.push(newValidator);

            emit ValidatorPendingActivation(newValidator);
        } else {
            // caller is a previously known validator
            ValidatorInfo storage existingValidator = $.validators[validatorIndex];
            // for already known validators, only `Exited` status is valid logical branch
            if (existingValidator.currentStatus != ValidatorStatus.Exited) {
                revert InvalidStatus(existingValidator.currentStatus);
            }

            existingValidator.activationEpoch = activationEpoch;
            existingValidator.currentStatus = ValidatorStatus.PendingActivation;
            existingValidator.ed25519Pubkey = ed25519Pubkey;
            existingValidator.blsPubkey = blsPubkey;

            emit ValidatorPendingActivation(existingValidator);
        }
    }

    /// @inheritdoc StakeManager
    function claimStakeRewards() external override whenNotPaused {
        // require caller is verified protocol validator - check NFT balance

        StakeManagerStorage storage $ = _stakeManagerStorage();

        // require caller is known
        uint16 validatorIndex = _getValidatorIndex($, msg.sender);
        if (validatorIndex == 0) revert NotValidator(msg.sender);

        uint256 rewards = _claimStakeRewards($);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @inheritdoc StakeManager
    function unstake() external override whenNotPaused {
        uint16 index = _getValidatorIndex(_stakeManagerStorage(), msg.sender);
        if (index == 0) revert NotValidator(msg.sender);

        // check caller is `Exited`
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        ValidatorStatus callerStatus = $.validators[index].currentStatus;
        if (callerStatus != ValidatorStatus.Exited) revert InvalidStatus(callerStatus);
        // set to `Undefined` to show stake was withdrawn, preventing reentrancy
        $.validators[index].currentStatus = ValidatorStatus.Undefined;

        uint256 stakeAndRewards = _unstake();

        emit RewardsClaimed(msg.sender, stakeAndRewards);
    }

    /// @inheritdoc IConsensusRegistry
    function exit() external whenNotPaused {
        // require caller is a known `ValidatorInfo` with `active` status
        uint16 validatorIndex = _getValidatorIndex(_stakeManagerStorage(), msg.sender);
        if (validatorIndex == 0) revert NotValidator(msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        ValidatorInfo storage validator = $.validators[validatorIndex];
        if (validator.currentStatus != ValidatorStatus.Active) {
            revert InvalidStatus(validator.currentStatus);
        }

        // enter validator in exit queue (will be ejected in 1.x epochs)
        uint32 exitEpoch = $.currentEpoch + 2;
        validator.exitEpoch = exitEpoch;
        validator.currentStatus = ValidatorStatus.PendingExit;

        emit ValidatorPendingExit(validator);
    }

    /// @inheritdoc StakeManager
    function getRewards(address ecdsaPubkey) public view virtual override returns (uint240 claimableRewards) {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        claimableRewards = _getRewards($, ecdsaPubkey);
    }

    /**
     *
     *   internals
     *
     */

    /// @dev Adds validators pending activation and ejects those pending exit
    function _updateValidatorSet(
        ConsensusRegistryStorage storage $,
        uint256 currentEpoch
    )
        internal
        returns (uint256 numActiveValidators)
    {
        ValidatorInfo[] storage validators = $.validators;

        // activate and eject validators in pending queues
        for (uint256 i; i < validators.length; ++i) {
            // cache validator in memory (but write to storage member)
            ValidatorInfo memory currentValidator = validators[i];

            if (currentValidator.currentStatus == ValidatorStatus.PendingActivation) {
                // activate validators which have waited at least a full epoch
                if (currentValidator.activationEpoch == currentEpoch) {
                    validators[i].currentStatus = ValidatorStatus.Active;

                    emit ValidatorActivated(validators[i]);
                }
            } else if (currentValidator.currentStatus == ValidatorStatus.PendingExit) {
                // eject validators which have waited at least a full epoch
                if (currentValidator.exitEpoch == currentEpoch) {
                    // mark as `Exited` but do not delete from array so validator can rejoin
                    validators[i].currentStatus = ValidatorStatus.Exited;

                    emit ValidatorExited(validators[i]);
                }
            }
        }

        numActiveValidators = _getValidators($, ValidatorStatus.Active).length;
    }

    /// @dev Stores the number of blocks finalized in previous epoch and the voter committee for the new epoch
    function _updateEpochInfo(
        ConsensusRegistryStorage storage $,
        uint16[] memory newCommitteeIndices,
        uint64 numBlocks
    )
        internal
        returns (uint32 newEpoch, uint64 newBlockHeight)
    {
        // cache epoch ring buffer's pointers in memory
        uint8 prevEpochPointer = $.epochPointer;
        uint8 newEpochPointer = (prevEpochPointer + 1) % 4;
        newBlockHeight = $.epochInfo[prevEpochPointer].blockHeight + numBlocks;

        // update new current epoch info
        $.epochInfo[newEpochPointer] = EpochInfo(newCommitteeIndices, newBlockHeight);
        $.epochPointer = newEpochPointer;
        newEpoch = ++$.currentEpoch;
    }

    /// @dev Checks the given committee size against the total number of active validators using below 3f + 1 BFT rule
    /// @notice To prevent the network from bricking in the case where validator churn leads to zero active validators,
    /// this function explicitly allows `numActiveValidators` to be zero so that the network can continue operating
    function _checkFaultTolerance(uint256 numActiveValidators, uint256 committeeSize) internal pure {
        if (numActiveValidators == 0) {
            return;
        } else if (committeeSize > numActiveValidators) {
            // sanity check committee size is less than number of active validators
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        }

        // if the total validator set is small, all must vote and no faults can be tolerated
        if (numActiveValidators <= 4 && committeeSize != numActiveValidators) {
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        } else {
            // calculate number of tolerable faults for given node count using 33% threshold
            uint256 tolerableFaults = numActiveValidators * 10_000 / 3;

            // committee size must be greater than tolerable faults
            uint256 minCommitteeSize = tolerableFaults / 10_000 + 1;
            if (committeeSize < minCommitteeSize) revert InvalidCommitteeSize(minCommitteeSize, committeeSize);
        }
    }

    function _incrementRewards(
        ConsensusRegistryStorage storage $,
        StakeInfo[] calldata stakingRewardInfos,
        uint32 newEpoch
    )
        internal
    {
        for (uint256 i; i < stakingRewardInfos.length; ++i) {
            uint16 index = stakingRewardInfos[i].validatorIndex;
            ValidatorInfo storage currentValidator = $.validators[index];
            // ensure client provided rewards only to known validators that were active in previous epoch
            if (newEpoch <= currentValidator.activationEpoch || currentValidator.activationEpoch == 0) {
                revert InvalidStatus(ValidatorStatus.PendingActivation);
            }

            address validatorAddr = currentValidator.ecdsaPubkey;
            uint240 epochReward = stakingRewardInfos[i].stakingRewards;

            _stakeManagerStorage().stakeInfo[validatorAddr].stakingRewards += epochReward;
        }
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

        if (status == ValidatorStatus.Undefined) {
            // provide undefined status `== uint8(0)` to get full validator array (of any status)
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

    function _getValidatorIndex(
        StakeManagerStorage storage $,
        address ecdsaPubkey
    )
        internal
        view
        returns (uint16)
    {
        return $.stakeInfo[ecdsaPubkey].validatorIndex;
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
    /// @notice Does not pause `finalizePreviousEpoch()`. Only accessible by `owner`
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Emergency function to unpause validator and stake management
    /// @notice Does not affect `finalizePreviousEpoch()`. Only accessible by `owner`
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
    /// @param initialValidators_ The initial validator set running Telcoin Network; will comprise the first voter committee
    function initialize(
        address rwTEL_,
        uint256 stakeAmount_,
        uint256 minWithdrawAmount_,
        ValidatorInfo[] memory initialValidators_,
        address owner_
    ) external initializer
    {
        if (initialValidators_.length == 0 || initialValidators_.length > type(uint16).max) {
            revert InitializerArityMismatch();
        }

        __Ownable_init(owner_);
        __Pausable_init();

        StakeManagerStorage storage $S = _stakeManagerStorage();

        // Set stake storage configs
        $S.rwTEL = rwTEL_;
        $S.stakeAmount = stakeAmount_;
        $S.minWithdrawAmount = minWithdrawAmount_;

        // handle first iteration as a special case, performing an extra iteration to compensate
        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        for (uint256 i; i <= initialValidators_.length; ++i) {
            if (i == 0) {
                // push a null ValidatorInfo to the 0th index in `validators` as 0 should be an invalid `validatorIndex`
                // this is because undefined validators with empty struct members break checks for uninitialized
                // validators
                $C.validators.push(
                    ValidatorInfo(
                        "",
                        bytes32(0x0),
                        address(0x0),
                        uint32(0),
                        uint32(0),
                        uint16(0),
                        bytes4(0),
                        ValidatorStatus.Undefined
                    )
                );

                continue;
            }

            // execution only reaches this point once `i == 1`
            ValidatorInfo memory currentValidator = initialValidators_[i - 1];

            // assert `validatorIndex` struct members match expected value
            if (currentValidator.blsPubkey.length != 48) revert InvalidBLSPubkey();
            if (currentValidator.ed25519Pubkey == bytes32(0x0)) revert InvalidEd25519Pubkey();
            if (currentValidator.ecdsaPubkey == address(0x0)) revert InvalidECDSAPubkey();
            if (currentValidator.activationEpoch != uint16(0)) revert InvalidEpoch(currentValidator.activationEpoch);
            if (currentValidator.currentStatus != ValidatorStatus.Active) {
                revert InvalidStatus(currentValidator.currentStatus);
            }
            if (currentValidator.validatorIndex != i) {
                revert InvalidIndex(currentValidator.validatorIndex);
            }

            $C.epochInfo[0].committeeIndices.push(uint16(i));
            _stakeManagerStorage().stakeInfo[currentValidator.ecdsaPubkey].validatorIndex = uint16(i);
            $C.validators.push(currentValidator);

            // todo: issue consensus NFTs to initial validators?

            emit ValidatorActivated(currentValidator);
        }
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
