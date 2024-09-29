// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// spec:
 // store validator ecdsaPubkeys (ecdsa, not bls)
 // recover signatures from those validator ecdsaPubkeys to store and to verify
 // func to return random validator set from prevrandao and numvalidators `_deriveValidatorSet()`
 // above func is called at end of each epoch to establish canonical voting committee for new epoch
 // reward/slash schema (merkleized, rewards go to staking contract)

// questions:
 // how long to store epoch info? ringbuffer(committee, numBlocksInEpoch) 256 epochs? less? 4 epochs?
 // how long to store known validators after they exit? expected num validators is low, but eventually array grows too big
    // when a validator rejoins the chain, bls & ed25519 keys should be rotated. how do consensus NFTs get handled for rejoiners?

// todos:
 // 0th index problem
 // rename validatorInfos -> validators && validatorInfosIndices -> validatorIndices
 // change indices to addresses

/**
 * @title ConsensusRegistry
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract manages consensus validator external keys, staking, and committees
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
contract ConsensusRegistry is UUPSUpgradeable, OwnableUpgradeable {

    error LowLevelCallFailure();
    error InitializerArityMismatch();
    error InvalidCommitteeSize(uint256 minCommitteeSize, uint256 providedCommitteeSize);
    error OnlySystemCall(address invalidCaller);
    error NotValidator(address ecdsaPubkey);
    error AlreadyDefined(address ecdsaPubkey);
    error InvalidProof(bytes proof);
    error InvalidStakeAmount(uint256 stakeAmount);
    error InvalidStatus(ValidatorStatus status);
    error InsufficientRewards(uint256 withdrawAmount);

    event ValidatorStaked(ValidatorInfo validator);
    event ValidatorRemoved(ValidatorInfo validator);

    enum ValidatorStatus {
        Undefined,
        PendingActivation,
        Active,
        Offline,
        PendingExit,
        Exited
    }

    struct ValidatorInfo { // todo: using each key type, sign over all other public keys
        address ecdsaPubkey;
        uint32 activationEpoch; // uint32 provides ~22000yr for 160s epochs (5s rounds)
        uint32 exitEpoch;
        bytes6 unused; // can be used for other data as well as expanded against activation and exit members
        ValidatorStatus currentStatus;
        bytes32 ed25519PubKey;
        bytes blsecdsaPubkey; // BLS Public Key is 48 bytes long
    }

    struct EpochInfo {
        uint256[] committeeIndices;
        uint16 numBlocks; // up to 65536 blocks per epoch - is this enough?
    }

    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint256 stakeAmount;
        uint256 minWithdrawAmount;
        uint32 currentEpoch; // can be resized
        mapping (uint256 => EpochInfo) epochInfo;
        // todo: handle 0th index in `validatorInfosIndex`
        mapping (address => uint256) validatorInfosIndex;
        ValidatorInfo[] validatorInfos;
        uint256[] currentCommittee; // validator indices of the current voter committee
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
    // todo: accept stakingRewardInfo (presumably an array of validators which created blocks or attested to them)
    function finalizePreviousEpoch(uint16 currentEpochBlocks, uint256[] calldata newCommitteeIndices, address[] calldata offlineValidatorAddresses /*, stakingRewardInfo*/) external {
        if (msg.sender != SYSTEM_ADDRESS) revert OnlySystemCall(msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        // increment `currentEpoch`
        uint256 newEpoch = ++$.currentEpoch; // cache in memory for use in resolving pending validators and voter committee
        // update full validator set by activating/ejecting pending validators & flagging offline ones
        _updateValidatorSet($, newEpoch, offlineValidatorAddresses);

        // store new committee and epoch info
        uint256 numActiveValidators = _getValidators($, ValidatorStatus.Active).length;
        _updateVoterCommittee($, currentEpochBlocks, newEpoch, numActiveValidators, newCommitteeIndices);
    }

    /// @dev Returns an array of `ValidatorInfo` structs that match the provided status for this epoch
    function getValidators(ValidatorStatus status) public view returns (ValidatorInfo[] memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /**
     *
     *   staking
     *
     */

    /// @dev Accepts the stake amount of native TEL and issues an activation request for the caller (validator) 
    function stake(bytes calldata blsPubkey, bytes calldata proofOfPossession, bytes32 ed25519Pubkey) external payable {
        // require caller is a verified protocol validator - how to do this? : must possess a consensus NFT

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        if (msg.value != $.stakeAmount) revert InvalidStakeAmount(msg.value);
        
        uint32 activationEpoch = $.currentEpoch + 2;
        uint256 validatorIndex = $.validatorInfosIndex[msg.sender];
        if (validatorIndex == 0) { // caller is a new validator
            // pull length before it is incremented and set in storage
            validatorIndex = $.validatorInfos.length;
            $.validatorInfosIndex[msg.sender] = validatorIndex;

            // push new validator to array
            ValidatorInfo memory newValidator = ValidatorInfo(msg.sender, activationEpoch, uint32(0), bytes6(0), ValidatorStatus.PendingActivation, ed25519Pubkey, blsPubkey);
            $.validatorInfos.push(newValidator);

            emit ValidatorStaked(newValidator);
        } else { // caller is a previously known validator
            ValidatorInfo storage existingValidator = $.validatorInfos[validatorIndex];
            // for already known validators, only `Exited` status is valid logical branch
            if (existingValidator.currentStatus != ValidatorStatus.Exited) revert InvalidStatus(existingValidator.currentStatus);

            existingValidator.activationEpoch = activationEpoch;
            existingValidator.currentStatus = ValidatorStatus.PendingActivation;

            emit ValidatorStaked(existingValidator);
        }
    }

    /// @dev Used for validators to claim their staking rewards for validating the network
    function claimStakeRewards() external {
        // require caller is verified protocol validator
        // require caller is a known `ValidatorInfo`
        // calculate rewards? or should that be written via syscall in every `finalizeEpoch()`
        // require rewards > minWithdrawAmount
        // wipe ledger
        // send rewards
        // if validator is exited, send staked balance + rewards
    }

    /// @dev Issues an exit request for a validator to be ejected from the active validator set
    function exit() external {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // require caller is a known `ValidatorInfo` with `active || offline` status
        uint256 validatorIndex = $.validatorInfosIndex[msg.sender];
        if (validatorIndex == 0) revert NotValidator(msg.sender);
        ValidatorInfo memory validator = $.validatorInfos[validatorIndex];
        if (validator.currentStatus != ValidatorStatus.Active || validator.currentStatus != ValidatorStatus.Offline) {
            revert InvalidStatus(validator.currentStatus);
        }

        // enter validator in exit queue (will be ejected in 1.x epochs)
        uint32 exitEpoch = $.currentEpoch + 2;
        $.validatorInfos[validatorIndex].exitEpoch = exitEpoch;
        $.validatorInfos[validatorIndex].currentStatus = ValidatorStatus.PendingExit;
    }

    /**
     *
     *   internals
     *
     */

    /// @dev Adds validators pending activation, ejects those pending exit, and flags those reported as offline by the client
    function _updateValidatorSet(ConsensusRegistryStorage storage $, uint256 currentEpoch, address[] calldata offlineValidatorAddresses) internal {
        ValidatorInfo[] storage validators = $.validatorInfos;
        
        // activate and eject validators in pending queues
        for (uint256 i; i < validators.length; ++i) {
            // cache validator in memory (but write to storage member)
            ValidatorInfo memory currentValidator = validators[i];

            if (currentValidator.currentStatus == ValidatorStatus.PendingActivation) {
                // activate validators which have waited at least a full epoch
                if (currentValidator.activationEpoch == currentEpoch) {
                    validators[i].currentStatus = ValidatorStatus.Active;
                }
            } else if (currentValidator.currentStatus == ValidatorStatus.PendingExit) {
                // eject validators which have waited at least a full epoch
                if (currentValidator.exitEpoch == currentEpoch) {
                    // mark as `Exited` but do not delete from array so validator can rejoin
                    validators[i].currentStatus = ValidatorStatus.Exited;
                }
            }
        }

        // flag validators reported as offline by the client
        for (uint256 i; i < offlineValidatorAddresses.length; ++i) {
            uint256 index = $.validatorInfosIndex[offlineValidatorAddresses[i]];
            if (index == 0) revert NotValidator(offlineValidatorAddresses[i]);

            $.validatorInfos[index].currentStatus = ValidatorStatus.Offline;
        }
    }

    /// @dev Stores the number of blocks finalized in previous epoch and the voter committee for the new epoch
    function _updateVoterCommittee(ConsensusRegistryStorage storage $, uint16 currentEpochBlocks, uint256 newEpoch, uint256 numActiveValidators, uint256[] memory newCommitteeIndices) internal {
        // ensure network is BFT for new epoch
        _checkFaultTolerance(numActiveValidators, newCommitteeIndices.length);

        // store previous epoch info now that it is known
        $.epochInfo[newEpoch - 1].numBlocks = currentEpochBlocks;
        // store new committee of validator indices
        $.epochInfo[newEpoch].committeeIndices = newCommitteeIndices;
    }

    /// @dev Checks the given committee size against the total number of active validators using the 2n + 1 BFT rule
    function _checkFaultTolerance(uint256 numActiveValidators, uint256 committeeSize) internal pure {
        // if the total validator set is small, all must vote
        if (numActiveValidators <= 4 && committeeSize != numActiveValidators) {
            revert InvalidCommitteeSize(numActiveValidators, committeeSize);
        } else {
            // calculate floored number of tolerable faults for given active node count
            uint256 n = numActiveValidators / 3;

            // identify and check committee size based on the 2n+1 rule
            uint256 minCommitteeSize = 3 * n + 1;
            if (committeeSize < minCommitteeSize) revert InvalidCommitteeSize(minCommitteeSize, committeeSize);
        }
    }

    // /// @dev Enters the given validator into a pending queue (`PendingActivation || PendingExit`)
    // function _queuePendingAction(ConsensusRegistryStorage storage $, uint256 validatorIndex, ValidatorStatus status) internal {
    //     if (status == ValidatorStatus.PendingActivation) {
    //         // // push to array (increments length)
    //         // uint32 activationEpoch = $.currentEpoch + 2;
    //         // $.validatorInfos.push(ValidatorInfo(msg.sender, activationEpoch, uint32(0), bytes6(0), status, ed25519Pubkey, blsPubkey));
    //     } else if (status == ValidatorStatus.PendingExit) {
    //         uint32 exitEpoch = $.currentEpoch + 2;
    //         $.validatorInfos[validatorIndex].exitEpoch = exitEpoch;
    //         $.validatorInfos[validatorIndex].currentStatus = status;
    //     }
    // }

    function _getValidators(ConsensusRegistryStorage storage $, ValidatorStatus status) internal view returns (ValidatorInfo[] memory) {
        ValidatorInfo[] memory allValidators = $.validatorInfos;

        if (status == ValidatorStatus.Undefined) {
        // provide undefined status `== uint8(0)` to get full validator list of any status
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
     *   upgradeability (devnet, testnet)
     *
     */

    /// @notice Must be replaced with a constructor in prod
    /// @dev Invoked once at genesis only
    /// @param initialValidators_ The initial set of validators running Telcoin Network
    /// @param initialCommitteeIndices_ An optional parameter declaring the initial voting committee (by validator index)
    function initialize(uint256 stakeAmount_, uint256 minWithdrawAmount_, ValidatorInfo[] calldata initialValidators_, uint256[] memory initialCommitteeIndices_, address owner) external initializer {
        if (initialValidators_.length < initialCommitteeIndices_.length) revert InitializerArityMismatch();

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        // push a null ValidatorInfo to the 0th index in `ValidatorInfos` as 0 should be an invalid `ValidatorInfosIndex`
        // this is because nonexistent validators will have struct members of 0 in future checks for known validators, ie when exiting
        $.validatorInfos.push(ValidatorInfo(address(0x0), uint32(0), uint32(0), bytes6(0), ValidatorStatus.Active, bytes32(0x0), ''));

        // set stake configs
        $.stakeAmount = stakeAmount_;
        $.minWithdrawAmount = minWithdrawAmount_;

        // store initial validator set
        for (uint256 i; i < initialValidators_.length; ++i) {
            ValidatorInfo calldata currentValidator = initialValidators_[i];
            uint256 nonZeroInfosIndex = i + 1;
            $.validatorInfosIndex[currentValidator.ecdsaPubkey] = nonZeroInfosIndex;
            $.validatorInfos.push(currentValidator);

            // todo: issue consensus NFTs to initial validators?

        }

        /// @dev first epoch supports either 1. an initial subset of validators as initial voting committee or 2. all validators vote
        if (initialCommitteeIndices_.length != 0) {
            for (uint256 i; i < initialCommitteeIndices_.length; ++i) {
                $.currentCommittee.push(initialCommitteeIndices_[i]);
            }
        }

        // note: must be removed for mainnet
        _transferOwnership(owner);
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}