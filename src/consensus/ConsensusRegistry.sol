// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ConsensusRegistry
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract manages consensus validator external keys, staking, and committees
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
contract ConsensusRegistry is Pausable, Ownable {
    error LowLevelCallFailure();
    error InvalidBLSPubkey();
    error InvalidEd25519Pubkey();
    error InvalidECDSAPubkey();
    error InvalidProof();
    error InitializerArityMismatch();
    error InvalidCommitteeSize(uint256 minCommitteeSize, uint256 providedCommitteeSize);
    error OnlySystemCall(address invalidCaller);
    error NotValidator(address ecdsaPubkey);
    error AlreadyDefined(address ecdsaPubkey);
    error InvalidStakeAmount(uint256 stakeAmount);
    error InvalidStatus(ValidatorStatus status);
    error InvalidIndex(uint16 validatorIndex);
    error InvalidEpoch(uint32 epoch);
    error InsufficientRewards(uint256 withdrawAmount);

    event ValidatorPendingActivation(ValidatorInfo validator);
    event ValidatorActivated(ValidatorInfo validator);
    event ValidatorPendingExit(ValidatorInfo validator);
    event ValidatorExited(ValidatorInfo validator);
    event NewEpoch(EpochInfo epoch);
    event RewardsClaimed(address claimant, uint256 rewards);

    enum ValidatorStatus {
        Undefined,
        PendingActivation,
        Active,
        PendingExit,
        Exited
    }

    struct ValidatorInfo {
        bytes blsPubkey; // BLS public key is 48 bytes long; BLS proofs are 96 bytes
        bytes32 ed25519Pubkey;
        address ecdsaPubkey;
        uint32 activationEpoch; // uint32 provides ~22000yr for 160s epochs (5s rounds)
        uint32 exitEpoch;
        uint16 validatorIndex; // up to 65535 validators
        bytes4 unused; // can be used for other data as well as expanded against activation and exit members
        ValidatorStatus currentStatus;
    }

    struct EpochInfo {
        uint256[] committeeIndices; // voter committee's validator indices
        uint16 blockHeight; // up to 65536 blocks per epoch - is this enough?
    }

    struct StakeInfo {
        uint16 validatorIndex;
        uint240 stakingRewards; // can be resized to uint104 (100bil $TEL)
    }

    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint256 stakeAmount;
        uint256 minWithdrawAmount;
        uint32 currentEpoch;
        uint8 epochPointer;
        EpochInfo[4] epochInfo;
        mapping(address => StakeInfo) stakeInfo;
        ValidatorInfo[] validators;
    }

    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.ConsensusRegistry")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant ConsensusRegistryStorageSlot =
        0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100;

    address public constant SYSTEM_ADDRESS = address(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);

    /**
     *
     *   consensus
     *
     */

    /// @notice Voting Validator Committee changes once every epoch (== 32 rounds)
    /// @notice Can only be called in a `syscall` context
    /// @dev Accepts the new epoch's committee of voting validators, which have been ascertained as active via handshake
    function finalizePreviousEpoch(
        uint16 numBlocks,
        uint256[] calldata newCommitteeIndices,
        StakeInfo[] calldata stakingRewardInfos
    )
        external
    {
        if (msg.sender != SYSTEM_ADDRESS) revert OnlySystemCall(msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // update epoch and ring buffer info
        (uint256 newEpoch, uint16 newBlockHeight) = _updateEpochInfo($, newCommitteeIndices, numBlocks);
        // update full validator set by activating/ejecting pending validators
        uint256 numActiveValidators = _updateValidatorSet($, newEpoch);

        // ensure new epoch's canonical network state is still BFT
        _checkFaultTolerance(numActiveValidators, newCommitteeIndices.length);

        // update each validator's claimable rewards with given amounts
        _incrementRewards($, stakingRewardInfos);

        emit NewEpoch(EpochInfo(newCommitteeIndices, newBlockHeight));
    }

    /// @dev Returns the current epoch
    function getCurrentEpoch() public view returns (uint32) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return $.currentEpoch;
    }

    /// @dev Returns an array of `ValidatorInfo` structs that match the provided status for this epoch
    function getValidators(ValidatorStatus status) public view returns (ValidatorInfo[] memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /// @dev Fetches the `validatorIndex` for a given validator address
    /// @notice A returned `validatorIndex` value of `0` is invalid
    function getValidatorIndex(address ecdsaPubkey) public view returns (uint16 validatorIndex) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        validatorIndex = _getValidatorIndex($, ecdsaPubkey);
    }

    /**
     *
     *   staking
     *
     */

    /// @dev Accepts the stake amount of native TEL and issues an activation request for the caller (validator)
    function stake(bytes calldata blsPubkey, bytes calldata blsSig, bytes32 ed25519Pubkey) external payable whenNotPaused {
        if (blsPubkey.length != 48) revert InvalidBLSPubkey();
        if (blsSig.length != 96) revert InvalidProof();

        // require caller is a verified protocol validator - how to do this? : must possess a consensus NFT
        // how to prove ownership of blsPubkey using blsSig - offchain?

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        if (msg.value != $.stakeAmount) revert InvalidStakeAmount(msg.value);

        uint32 activationEpoch = $.currentEpoch + 2;
        uint16 validatorIndex = _getValidatorIndex($, msg.sender);
        if (validatorIndex == 0) {
            // caller is a new validator and will be appended to end of array
            validatorIndex = uint16($.validators.length);
            $.stakeInfo[msg.sender].validatorIndex = validatorIndex;

            // push new validator to array
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

    /// @dev Used for validators to claim their staking rewards for validating the network
    function claimStakeRewards() external whenNotPaused {
        // require caller is verified protocol validator - check NFT balance

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // require caller is known
        uint16 validatorIndex = _getValidatorIndex($, msg.sender);
        if (validatorIndex == 0) revert NotValidator(msg.sender);

        // calculate rewards? or should that be written via syscall in every `finalizeEpoch()`
        uint256 rewards = $.stakeInfo[msg.sender].stakingRewards;
        if (rewards < $.minWithdrawAmount) revert InsufficientRewards(rewards);

        // wipe ledger for reentrancy and send
        $.stakeInfo[msg.sender].stakingRewards = 0;
        (bool r,) = msg.sender.call{ value: rewards }("");
        require(r);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @dev Returns previously staked funds and accrued rewards, if any, to the calling validator
    /// @notice May only be called after fully exiting
    function unstake() external whenNotPaused {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        uint16 index = _getValidatorIndex($, msg.sender);
        if (index == 0) revert NotValidator(msg.sender);

        // check caller is `Exited`
        ValidatorStatus callerStatus = $.validators[index].currentStatus;
        if (callerStatus != ValidatorStatus.Exited) revert InvalidStatus(callerStatus);
        // set to `Undefined` to show stake was withdrawn, preventing reentrancy
        $.validators[index].currentStatus = ValidatorStatus.Undefined;

        // wipe ledger and send staked balance + rewards
        uint256 stakeAndRewards = $.stakeAmount + $.stakeInfo[msg.sender].stakingRewards;
        $.stakeInfo[msg.sender].stakingRewards = 0;
        (bool r,) = msg.sender.call{ value: stakeAndRewards }("");
        require(r);

        emit RewardsClaimed(msg.sender, stakeAndRewards);
    }

    /// @dev Issues an exit request for a validator to be ejected from the active validator set
    function exit() external whenNotPaused {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // require caller is a known `ValidatorInfo` with `active` status
        uint16 validatorIndex = _getValidatorIndex($, msg.sender);
        if (validatorIndex == 0) revert NotValidator(msg.sender);
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
        uint256[] memory newCommitteeIndices,
        uint16 numBlocks
    )
        internal
        returns (uint256 newEpoch, uint16 newBlockHeight)
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
    function _checkFaultTolerance(uint256 numActiveValidators, uint256 committeeSize) internal pure {
        // sanity check committee size is less than number of active validators
        if (committeeSize > numActiveValidators) {
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        }

        // if the total validator set is small, all must vote and no faults can be tolerated
        if (numActiveValidators <= 4 && committeeSize != numActiveValidators) {
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        } else {
            // calculate number of tolerable faults for given node count using 33% threshold 
            uint256 tolerableFaults = numActiveValidators / 3;

            // committee size must be greater than tolerable faults
            uint256 minCommitteeSize = tolerableFaults + 1;
            if (committeeSize < minCommitteeSize) revert InvalidCommitteeSize(minCommitteeSize, committeeSize);
        }
    }

    function _incrementRewards(ConsensusRegistryStorage storage $, StakeInfo[] calldata stakingRewardInfos) internal {
        for (uint256 i; i < stakingRewardInfos.length; ++i) {
            uint16 index = stakingRewardInfos[i].validatorIndex;
            address validatorAddr = $.validators[index].ecdsaPubkey;
            uint240 epochReward = stakingRewardInfos[i].stakingRewards;

            $.stakeInfo[validatorAddr].stakingRewards += epochReward;
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
        ConsensusRegistryStorage storage $,
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

    /// @notice Must be replaced with a constructor in prod
    /// @dev Invoked once at genesis only
    /// @param initialValidators_ The initial set of validators running Telcoin Network
    /// @param initialCommitteeIndices_ Optional parameter declaring initial voting committee (by index)
    constructor(
        uint256 stakeAmount_,
        uint256 minWithdrawAmount_,
        ValidatorInfo[] memory initialValidators_,
        uint256[] memory initialCommitteeIndices_,
        address owner
    ) Ownable(owner) {
        if (initialValidators_.length == 0) revert InitializerArityMismatch();
        if (initialValidators_.length < initialCommitteeIndices_.length) revert InitializerArityMismatch();

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // push a null ValidatorInfo to the 0th index in `validators` as 0 should be an invalid `validatorIndex`
        // this is because undefined validators with empty struct members break checks for uninitialized validators
        $.validators.push(
            ValidatorInfo(
                "", bytes32(0x0), address(0x0), uint32(0), uint32(0), uint16(0), bytes4(0), ValidatorStatus.Undefined
            )
        );

        // Set stake configs
        $.stakeAmount = stakeAmount_;
        $.minWithdrawAmount = minWithdrawAmount_;

        // todo: how should these validators stake at genesis? lock on mainnet pre-genesis?
        for (uint256 i; i < initialValidators_.length; ++i) {
            ValidatorInfo memory currentValidator = initialValidators_[i];
            
            // assert `validatorIndex` struct members match expected value
            if (currentValidator.blsPubkey.length != 48) revert InvalidBLSPubkey();
            if (currentValidator.ed25519Pubkey == bytes32(0x0)) revert InvalidEd25519Pubkey();
            if (currentValidator.ecdsaPubkey == address(0x0)) revert InvalidECDSAPubkey();
            if (currentValidator.activationEpoch != uint16(0)) revert InvalidEpoch(currentValidator.activationEpoch);
            if (currentValidator.currentStatus != ValidatorStatus.Active) revert InvalidStatus(currentValidator.currentStatus);
            uint256 nonZeroInfosIndex = i + 1;
            if (nonZeroInfosIndex != currentValidator.validatorIndex) {
                revert InvalidIndex(currentValidator.validatorIndex);
            }

            // store initial validator set
            $.stakeInfo[currentValidator.ecdsaPubkey].validatorIndex = uint16(nonZeroInfosIndex);
            $.validators.push(currentValidator);

            // todo: issue consensus NFTs to initial validators?

            // emit event for activated validator
            emit ValidatorActivated(currentValidator);
        }

        // if provided, initial subset of validators is initial voting committee; else all initial validators vote
        if (initialCommitteeIndices_.length != 0) {
            $.epochInfo[0].committeeIndices = initialCommitteeIndices_;
        } else {
            // construct array of all genesis validator indices
            uint256[] memory allInitialValidatorIndices = new uint256[](initialValidators_.length);
            for (uint256 i; i < allInitialValidatorIndices.length; ++i) {
                // store all initial validator indices in case all should vote in first epoch
                allInitialValidatorIndices[i] = i + 1;
            }

            $.epochInfo[0].committeeIndices = allInitialValidatorIndices;
        }
    }

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
}
