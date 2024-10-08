// SPDX-License-Identifier: MIT
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

    /**
     *
     *   consensus
     *
     */

    /// @inheritdoc IConsensusRegistry
    function finalizePreviousEpoch(
        address[] calldata newCommittee,
        StakeInfo[] calldata stakingRewardInfos
    )
        external
        onlySystemCall
        returns (uint32 newEpoch, uint256 numActiveValidators)
    {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // update epoch and ring buffer info
        newEpoch = _updateEpochInfo($, newCommittee);
        // update full validator set by activating/ejecting pending validators
        numActiveValidators = _updateValidatorSet($, newEpoch);

        // ensure new epoch's canonical network state is still BFT
        _checkFaultTolerance(numActiveValidators, newCommittee.length);

        // update each validator's claimable rewards with given amounts
        _incrementRewards($, stakingRewardInfos, newEpoch);

        emit NewEpoch(EpochInfo(newCommittee, uint64(block.number)));
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
     *   validators
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

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        uint16 validatorIndex = _getValidatorIndex(_stakeManagerStorage(), msg.sender);
        // todo: should ConsensusNFT be issued prior to stake action?
        // _checkConsensusNFTOwnership(validatorIndex, msg.sender);

        uint32 activationEpoch = $.currentEpoch + 2;
        if (validatorIndex == 0) {
            // caller is a new validator; update its index in `StakeManager` storage
            validatorIndex = uint16($.validators.length);
            _stakeManagerStorage().stakeInfo[msg.sender].validatorIndex = validatorIndex;

            // issue a new ConsensusNFT
            _mint(msg.sender, validatorIndex);

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

            // require caller owns a ConsensusNFT
            _checkConsensusNFTOwnership(msg.sender, validatorIndex);

            // for already known validators, only `Exited` status is valid logical branch
            _checkValidatorStatus($, validatorIndex, ValidatorStatus.Exited);

            existingValidator.activationEpoch = activationEpoch;
            existingValidator.currentStatus = ValidatorStatus.PendingActivation;
            existingValidator.ed25519Pubkey = ed25519Pubkey;
            existingValidator.blsPubkey = blsPubkey;

            emit ValidatorPendingActivation(existingValidator);
        }
    }

    /// @inheritdoc StakeManager
    function claimStakeRewards() external override whenNotPaused {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // require caller is known by this registry
        uint16 validatorIndex = _checkKnownValidatorIndex($, msg.sender);
        // require caller owns the ConsensusNFT where `validatorIndex == tokenId`
        _checkConsensusNFTOwnership(msg.sender, validatorIndex);

        uint256 rewards = _claimStakeRewards($);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @inheritdoc IConsensusRegistry
    function exit() external whenNotPaused {
        // require caller is known by this registry
        uint16 validatorIndex = _checkKnownValidatorIndex(_stakeManagerStorage(), msg.sender);
        // require caller owns the ConsensusNFT where `validatorIndex == tokenId`
        _checkConsensusNFTOwnership(msg.sender, validatorIndex);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // require caller status is `Active`
        _checkValidatorStatus($, validatorIndex, ValidatorStatus.Active);

        ValidatorInfo storage validator = $.validators[validatorIndex];

        // enter validator in exit queue (will be ejected in 1.x epochs)
        uint32 exitEpoch = $.currentEpoch + 2;
        validator.exitEpoch = exitEpoch;
        validator.currentStatus = ValidatorStatus.PendingExit;

        emit ValidatorPendingExit(validator);
    }


    /// @inheritdoc StakeManager
    function unstake() external override whenNotPaused {
        // require caller is known by this registry
        uint16 validatorIndex = _checkKnownValidatorIndex(_stakeManagerStorage(), msg.sender);
        // require caller owns the ConsensusNFT where `validatorIndex == tokenId`
        _checkConsensusNFTOwnership(msg.sender, validatorIndex);

        // burn the ConsensusNFT; can be reversed if caller rejoins as validator 
        _burn(validatorIndex);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        // require caller status is `Exited`
        _checkValidatorStatus($, validatorIndex, ValidatorStatus.Exited);
        // set to `Undefined` to show stake was withdrawn, preventing reentrancy
        $.validators[validatorIndex].currentStatus = ValidatorStatus.Undefined;

        uint256 stakeAndRewards = _unstake();

        emit RewardsClaimed(msg.sender, stakeAndRewards);
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
        address[] memory newCommittee
    )
        internal
        returns (uint32 newEpoch)
    {
        // cache epoch ring buffer's pointers in memory
        uint8 prevEpochPointer = $.epochPointer;
        uint8 newEpochPointer = (prevEpochPointer + 1) % 4;

        // update new current epoch info
        address[] storage currentcommittee = $.futureEpochInfo[newEpochPointer].committee;
        $.epochInfo[newEpochPointer] = EpochInfo(currentcommittee, uint64(block.number));
        $.epochPointer = newEpochPointer;
        newEpoch = ++$.currentEpoch;

        // update future epoch info
        uint8 twoEpochsInFuturePointer = (newEpochPointer + 2) % 4;
        $.futureEpochInfo[twoEpochsInFuturePointer].committee = newCommittee;
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

    /// @dev Reverts if the provided address doesn't correspond to an existing `validatorIndex`
    function _checkKnownValidatorIndex(StakeManagerStorage storage $, address caller) private view returns (uint16 validatorIndex) {
        validatorIndex = _getValidatorIndex($, caller);
        if (validatorIndex == 0) revert NotValidator(caller);
    }

    /// @dev Reverts if the provided validator's status doesn't match the provided `requiredStatus`
    function _checkValidatorStatus(ConsensusRegistryStorage storage $, uint16 validatorIndex, ValidatorStatus requiredStatus) private {
        ValidatorStatus status = $.validators[validatorIndex].currentStatus;
        if (status != requiredStatus) revert InvalidStatus(status);
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

    function _getValidatorIndex(StakeManagerStorage storage $, address ecdsaPubkey) internal view returns (uint16) {
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

            // first three epochs use initial validators as committee
            for (uint256 j; j <= 2; ++j) {
                $C.epochInfo[j].committee.push(currentValidator.ecdsaPubkey);
            }

            uint256 validatorIndex = i;
            _stakeManagerStorage().stakeInfo[currentValidator.ecdsaPubkey].validatorIndex = uint16(validatorIndex);
            $C.validators.push(currentValidator);

            __ERC721_init("ConsensusNFT", "CNFT");
            _mint(currentValidator.ecdsaPubkey, validatorIndex);

            emit ValidatorActivated(currentValidator);
        }
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
