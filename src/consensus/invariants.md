# ConsensusRegistry invariants

**consensus**

- consensus-related functions `concludeEpoch` `applyIncentives` `applySlashes` must never revert or otherwise interrupt protocol operation
- concludeEpoch must be the final system call of the epoch, succeeding reward and slash system calls
- committee size must never reach 0 or more than the number of effectively active (active and pendingexit) validators in the new epoch.

**validators**

- validator statuses are one directional; ie Active cannot revert to PendingActive, PendingExit cannot revert to Active, and so forth
- only staked validators can begin activation
- pending activation and pending exit validators are also considered active since exit queue is updated before checking committee size
- only exited validators can unstake (unless forcibly burned)
- retired validator addresses can never rejoin
- unvariant: validator storage vector can eventually grow to exceed gas limits but this will be a good problem to have and storage can be optimized

**stake**

- stake balances and rewards can never overflow uint232, even with significant inflation or use of the precision factor
- the only way to withdraw funds from the ConsensusRegistry and Issuance contract are during reward claim or full validator retirement (stake + rewards)
- stake configs must take effect in the next epoch, not current
- consensus burns must never push committees or validator set to invalid state
- consensus burned tokenIDs must not cause a revert for system called epoch actions
- ConsensusRegistry only ever holds staked funds, including on behalf of the initial validator set at network genesis (rest to InterchainTEL)
- Issuance only ever holds epoch reward funds, less claims
- claims can revert if Issuance contract runs dry (eg TAO governance problem) but rewards ledger must continue being updated by applyIncentives or applySlahes
