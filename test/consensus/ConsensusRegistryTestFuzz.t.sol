// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { IConsensusRegistry } from "src/consensus/interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "src/consensus/SystemCallable.sol";
import { StakeManager } from "src/consensus/StakeManager.sol";
import { StakeInfo, IStakeManager } from "src/consensus/interfaces/IStakeManager.sol";
import { RWTEL } from "src/RWTEL.sol";
import { ConsensusRegistryTestUtils } from "./ConsensusRegistryTestUtils.sol";

/// @dev Fuzz test module separated into new file with extra setup to avoid `OutOfGas`
contract ConsensusRegistryTestFuzz is ConsensusRegistryTestUtils, Test {
    function setUp() public {
        consensusRegistry = ConsensusRegistry(0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        vm.etch(address(consensusRegistry), type(ERC1967Proxy).runtimeCode);
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(consensusRegistry), implementationSlot, bytes32(abi.encode(address(consensusRegistryImpl))));
        consensusRegistry.initialize(address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, crOwner);

        sysAddress = consensusRegistry.SYSTEM_ADDRESS();

        // deal RWTEL max TEL supply to test reward distribution
        vm.deal(address(rwTEL), telMaxSupply);

        // to prevent exceeding block gas limit, `mint(newValidator)` is performed in setup
        for (uint256 i; i < MAX_MINTABLE; ++i) {
            // account for initial validators
            uint256 tokenId = i + 5;
            address newValidator = address(uint160(uint256(keccak256(abi.encode(tokenId)))));

            // deal `stakeAmount` funds and prank governance NFT mint to `newValidator`
            vm.deal(newValidator, stakeAmount);
            vm.prank(crOwner);
            consensusRegistry.mint(newValidator, tokenId);
        }
    }

    function testFuzz_concludeEpoch(uint24 numValidators, uint232 fuzzedRewards) public {
        numValidators = uint24(bound(uint256(numValidators), 4, 4000)); // fuzz up to 4k validators
        fuzzedRewards = uint232(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        // Finalize epoch once to reach `PendingExit` for `validator0`
        vm.prank(sysAddress);
        // provide `committeeSize == 3` since there are now only 3 active validators
        consensusRegistry.concludeEpoch(new address[](4));

        // activate validators via `stake()` and construct `newCommittee` array as pseudorandom subset (1/3)
        uint256 numActiveValidators = uint256(numValidators) + 4;
        uint256 committeeSize = (uint256(numActiveValidators) * 10_000) / 3 / 10_000 + 1; // address precision loss
        address[] memory newCommittee = new address[](committeeSize);
        uint256 committeeCounter;
        for (uint256 i; i < numValidators; ++i) {
            // recreate `newValidator` address minted a ConsensusNFT in `setUp()` loop
            address newValidator = address(uint160(uint256(keccak256(abi.encode(i)))));

            // create random new validator keys
            bytes memory newBLSPubkey = _createRandomBlsPubkey(i);

            vm.deal(newValidator, stakeAmount);
            vm.prank(newValidator);
            consensusRegistry.stake{ value: stakeAmount }(newBLSPubkey);

            // push first third of new validators to new committee
            if (committeeCounter < newCommittee.length) {
                newCommittee[committeeCounter] = newValidator;
                committeeCounter++;
            }
        }

        // Finalize epoch twice to reach activationEpoch for validators entered in the `stake()` loop
        vm.startPrank(sysAddress);
        // provide `committeeSize == 3` since there are now only 3 active validators
        consensusRegistry.concludeEpoch(new address[](4));
        consensusRegistry.concludeEpoch(newCommittee);

        uint256 numRecipients = newCommittee.length; // all committee members receive rewards
        uint232 rewardPerValidator = uint232(fuzzedRewards / numRecipients);
        // construct `committeeRewards` array to compensate voting committee equally (total `fuzzedRewards` divided
        // across committee)
        StakeInfo[] memory committeeRewards = new StakeInfo[](numRecipients);
        for (uint256 i; i < newCommittee.length; ++i) {
            uint256 recipientTokenId = consensusRegistry.getValidatorTokenId(newCommittee[i]);
            committeeRewards[i] = StakeInfo(uint24(recipientTokenId), rewardPerValidator);
        }

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.NewEpoch(IConsensusRegistry.EpochInfo(newCommittee, uint64(block.number + 1)));
        // increment rewards by finalizing an epoch with a `StakeInfo` for constructed committee (new committee not
        // relevant)
        consensusRegistry.concludeEpoch(newCommittee);
        consensusRegistry.incrementRewards(committeeRewards);
        vm.stopPrank();

        // Check rewards were incremented for each committee member
        for (uint256 i; i < newCommittee.length; ++i) {
            uint256 tokenId = consensusRegistry.getValidatorTokenId(newCommittee[i]);
            address committeeMember = consensusRegistry.getValidatorByTokenId(tokenId).ecdsaPubkey;
            uint256 updatedRewards = consensusRegistry.getRewards(committeeMember);
            assertEq(updatedRewards, rewardPerValidator);
        }
    }

    // Test for successful claim of staking rewards
    function testFuzz_claimStakeRewards(uint232 fuzzedRewards) public {
        fuzzedRewards = uint232(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        vm.prank(crOwner);
        uint256 tokenId = 5;
        address validator5 = address(uint160(uint256(keccak256(abi.encode(tokenId)))));
        consensusRegistry.mint(validator5, tokenId);

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // Capture initial rewards info
        uint256 initialRewards = consensusRegistry.getRewards(validator5);

        // activate validator5
        vm.prank(validator5);
        consensusRegistry.activate();

        uint256 numActiveValidators = consensusRegistry.getValidators(ValidatorStatus.Active).length;
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](numActiveValidators));
        // consensusRegistry.concludeEpoch(new address[](numActiveValidators + 1));

        // Simulate earning rewards by finalizing an epoch with a `StakeInfo` for validator5
        StakeInfo[] memory validator5Rewards = new StakeInfo[](1);
        validator5Rewards[0] = StakeInfo(uint24(tokenId), fuzzedRewards);
        consensusRegistry.concludeEpoch(new address[](4));
        consensusRegistry.incrementRewards(validator5Rewards);
        vm.stopPrank();

        // Check rewards were incremented
        uint256 updatedRewards = consensusRegistry.getRewards(validator5);
        assertEq(updatedRewards, initialRewards + fuzzedRewards);

        // Capture initial validator balance
        uint256 initialBalance = validator5.balance;

        // Check event emission and claim rewards
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.RewardsClaimed(validator5, fuzzedRewards);
        vm.prank(validator5);
        consensusRegistry.claimStakeRewards();

        // Check balance after claiming
        uint256 updatedBalance = validator5.balance;
        assertEq(updatedBalance, initialBalance + fuzzedRewards);
    }
}
