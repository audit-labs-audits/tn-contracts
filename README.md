# Telcoin Network Smart Contracts

//todo: update this file

## things to write about:

- ITS config (testnet, mainnet)
  // note that rwTEL interchainTokenSalt and interchainTokenId are the same as (derived from) canonicalTEL
  // they are used to deploy interchain TEL contracts to new chains other than TN (obviated by genesis)
  // tokenId derived from canonicalTEL is used for new interchain TEL
  // salt derived from canonicalTEL is used for new interchain TEL tokens

  - canonicalTEL is on ethereum => (create3Salt, interchainTokenId, LOCK_UNLOCK token manager)
    - (create3Salt, interchainTokenId) => allChains(interchainTEL, NATIVE_INTERCHAIN token manager)
      - (interchainTEL, MINT_BURN token manager) on TN is at same address as allChains but with RWTEL logic on address(interchainTEL)
  - verifiers: how many, how often to rotate
  - rwtel recoverable time, governance address (safe)
  - ITS proxy owners/operators (gatewayOwner, gatewayOperator, gas collector, gas owner, itsOwner, itsOperator, itfOwner, , )
  - flowlimits: how much tel flow to limit per 6 hours, which address to set this (rwtelTMOperator)
  - rwtel pausability?
  - user flow

    - ethereumITS::interchainTransfer(amt=100) // issue interchain gmp msg for 1 ERC20 tel of decimals==2
    - await Axelar Network validation (subscriber relayer forwards msg, verifiers vote)
    - interchain transfer msg delivered to TN gateway by relayer, then includer executes
    - `ITS::execute()` calls mint() on TN "interchainToken" (rwTEL)
    - rwTEL::mint() sends native TEL of amt\*10e16 (10e18 == 1 TEL)

    - tnITS::interchainTransfer(amt=10e18) // issue interchain gmp msg for 1 native TEL of decimals==18
    - within `tnITS::interchainTransfer()`, a call to `rwTEL::burn(amt)` is made, which:
      1. calls `wTEL::unwrap(amt)` to reclaim underlying TEL using native decimals, and then
      2.

  - decimals conversion handled at TN TokenHandler, because `amount` is set in payloads constructed and submitted on the source chain. Thus the conversion must happen at the interchain transfer's mint/burn execution point, both of which are carried out by delegatecall to interchain TokenHandler.

  - "upgrade" of ethereum TEL from canonical to interchain token becomes possible with some caveats: an upgrade to `ITF::deployInterchainToken()` and a requirement that TEL be migrated to telcoin-network before exiting in upgraded form. In essence native TEL can be upgraded to interchain TEL after passing through the rwTEL (TN's impl for interchain ERC20 TEL). Using the ITF fn, we would be able to deploy interchain TEL (to ITS::create3 address- ie interchainTEL&rwTEL) on all chains incl Ethereum. It could match native&rwTEL's 18 decimals, add supply inflation, etc- the only limitation is that ethereum TEL has to be bridged to TN first and then back to remote chains like ethereum in order to arrive at the new interchain ethereum contract. A side effect arising from ITS being immutable on all other chains is that we will not be able to perform such an upgrade if we pre-bridge existingTEL to its interchain create3 version before launching TN. The "canonical shift" from ethereum to TN must happen first.

## ConsensusRegistry

### Role

The Telcoin Network ConsensusRegistry contract serves as a single onchain source of truth for consensus-related items which need to be easily accessible across all TN nodes.

These items include

1.  **ConsensusNFT Whitelist** To onboard, new validators must obtain a `ConsensusNFT` through Telcoin governance. The ConsensusRegistry contract manages this NFT ledger.
2.  Managing TEL staking mechanisms, such as locking stake for governance-approved validators as well as tracking and distributing (pull-based) rewards for validation services
3.  Managing the active validator set, autonomously bringing them through pending queues for activation and exit
4.  Storing historical epoch information which includes epoch block heights and voting validator committees. Voter committees are predetermined by the protocol and stored two epochs in the future.

To keep this information up to date, the protocol maintains contract state via the use of a system call to `ConsensusRegistry::concludeEpoch()` at the end of each epoch. This action is what kickstarts the beginning of each new epoch.

### Mechanisms

#### The contract's most frequent entrypoint: `concludeEpoch()`

- **Finalize Epoch:** The `concludeEpoch` function is responsible for finalizing the previous epoch, updating the validator set, storing new epoch information, and incrementing staking rewards. Rewards may then be claimed by validators at their discretion.
- **System Call Context** `concludeEpoch()` may only be called by the client via `system call`, which occurs every epoch. This logic is abstracted into the `SystemCallable` module.

#### ConsensusNFT Whitelist

To join Telcoin Network as a validator, node operators first must be approved by Telcoin governance. Once approved, validators will be issued a `ConsensusNFT` serving as a permissioned validator whitelist. Only the contract owner, an address managed by Telcoin governance, can issue these NFTs via `ConsensusRegistry::mint()`

The ERC721 `tokenId` of each validator's token corresponds to their validator uid, termed `validatorIndex` in the registry's implementation.

#### Validator Registration and Staking

Once issued a `ConsensusNFT`, validators may enter the pending activation queue at their discretion by staking a fixed amount of native TEL and providing their public keys via `ConsensusRegistry::stake()`

Below, we follow the general lifecycle of a new validator in roughly chronological order.

1. **Validator Registration**

   - **Stake:** Validators with a `ConsensusNFT` call the `stake()` function along with the required stake amount, providing their BLS public key, BLS signature, and ED25519 public key.
   - **Pending Activation:** Upon successful staking, the validator's status is set to `PendingActivation`, and its activation epoch is recorded to be 2 epochs in the future. After awaiting the remainder of the current epoch and then one full epoch, its status will automatically be updated to `Active`

2. **Activation**

   - **Epoch Advancement:** At the end of each epoch, the `concludeEpoch()` function is system called directly from the client. This function automatically processes the `PendingActivation` and `PendingExit` queues. Thus, validators in the `PendingActivation` (or `PendingExit`) state are set to `Active` (or `Exited`) state if their activation (or exit) epoch has been reached by advancing an epoch.

3. **Reversible Exit**

   - **Exit Requests** Once active, validators may call the `exit()` function to initiate an exit from the network. These exits are reversible and may be used for node maintenance or key rotation. To permanently forgoe validator status, exited validators must then reclaim their stake and burn their ConsensusNFT using `unstake()`
   - **Pending Exit** Upon calling `exit()`, the validator's status is set to `PendingExit`, and their exit epoch is recorded to be 2 epochs in the future. The pending queue is handled identically to the `PendingActivation` process described above.

4. **Rejoining**

   - **Rejoin Requests** Once exited, validators may call the `rejoin()` function to initiate a rejoin request. They may provide new keys if desired.
   - **Pending Activation** Upon calling `rejoin()`, the validator will be entered into the `PendingActivation` queue

5. **Unstaking**
   - **Withdraw Stake:** Once in the `Exited` state, validators can call the `unstake` function to withdraw their original stake amount along with any accrued rewards.
   - Once unstaked, a validator can no longer `rejoin()`, as their `ConsensusNFT` is burned and their validator is set to `UNSTAKED` state, which is unrecoverable. Should an unstaked validator want to resume validating the network, they must reapply to Telcoin governance and be re-issued a new `ConsensusNFT`

### ConsensusRegistry storage layout for genesis

The registry contract uses explicit namespaced storage to sandbox sensitive state by category and prevent potential overwrites during upgrades (it is an upgradeable proxy for testnet +devnet). Namespaced sections are separated by "---" blocks

Storage configuration at genesis is generated by recording the storage slots written by simulating deployment of the ConsensusRegistry proxy contract and simulating a call to its `ConsensusRegistry::initialize()` function.

These simulations are performed by the utility in `script/GenerateConsensusRegistryStorage.s.sol`, which outputs a yaml file at `deployments/consensus-registry-storage.yaml`. The canonical yaml file is then read by the protocol to include its storage configurations at genesis.

## RWTEL Module

### Role

The Recoverable Wrapped Telcoin (rwTEL) contract serves as TN's bridge architecture entry and exit point with respect to execution. In simpler terms, this module performs the actual delivery of inbound $TEL from Ethereum ("ethTEL") and exports outbound $TEL ("TEL") which has been settled by waiting out the RecoverableWrapper's timelock.

### Design Decisions

RWTEL.sol combines Circle Research's recoverable wrapper utility with the required Axelar parent contract, `InterchainTokenExecutable`, which provides the bridge setup's execution interface `_executeWithInterchainToken()` that must be implemented to support Axelar ITS infrastructure as it will be called by the Axelar InterchainTokenService.

### Mechanisms

The only way to mint TEL on Telcoin-Network is via bridging through the RWTEL module. The high-level concept of secure TN bridging for a TEL holder pre-genesis is:

- **A.** Own the $TEL ERC20 on Ethereum (which we have been calling "ethTEL")
- **B.** Perform an ERC20 spend approval for the Axelar External Gateway
- **C.** Submit a bridge message to Axelar Network for verification by locking ethTEL in the ITS TokenManager for ethTEL on Ethereum

Because ethTEL is the canonical $TEL token which will be used as native currency on TN (in the form of TEL), a way for incoming ethTEL ERC20 tokens to be converted to a non-ERC20 base layer currency must be implemented at the bridge entrypoint. This is one primary function of the RWTEL module.

Without this functionality, incoming ethTEL from Ethereum mainnet would be delivered as the ERC20 wTEL and cannot be unwrapped to native TEL without already having some to pay gas. In such a scenario, no entity would even be able to transact on TN as there would be no currency to pay gas with.

#### Axelar Interchain Token Service integration

todo:
Invariants:
ethTEL is a canonical interchain token

##### Flow:

On Ethereum:

1. Register ethTEL metadata with Axelar chain's ITS hub using Ethereum InterchainTokenService

`its.registerTokenMetadata(ethTEL, gasValue)`

2. Register ethTEL canonical interchain tokenId and deploy its TokenManager using Ethereum InterchainTokenFactory.

`itFactory.registerCanonicalInterchainToken(ethTEL)`

##### Note that the TEL canonical interchain tokenId is derived using the `InterchainTokenFactory::returnedInterchainTokenSalt()` for ethTEL

On Telcoin-Network:
todo: genesis

##### Incoming TEL from Ethereum is delivered as native TEL on Telcoin-Network

To unlock native TEL from RWTEL, Axelar Network ensures that ethTEL has been locked on Ethereum by requiring a quorum of TN verifiers to independently validate incoming bridge messages. Once verified, messages are routed through the InterchainTokenService, ending at `RWTEL::_executeWithInterchainToken()` which delivers native TEL to the recipient

##### Outbound TEL from Telcoin-Network to supported supported interchain blockchains

To bridge native TEL off of Telcoin-Network, it must first be double-wrapped to wTEL and then rwTEL. For security, the RWTEL module enforces that only settled `RecoverableWrapper` token balances may be bridged. Only RWTEL balances which have awaited the module's recoverable window are considered settled, which provides time-based assurance that all outbound native TEL is sourced legitimately.

#### Native TEL at Genesis

The equivalent of ethTEL's total supply is provided to the RWTEL module as native TEL at network genesis.

While the mirrored total supply of TEL native currency technically "exists" at the RWTEL address from network genesis, it is locked in the RWTEL module and probabilistically inaccessible thus equivalent to being "burned/unminted". Native TEL can only be unlocked by an interchain bridge message which locks a corresponding amount of ethTEL ERC20 token in its TokenManager on Ethereum. This binary relationship of lock <> release state between chains is what maintain's the token supply's integrity across chains.

- **Security Posture:** Achieving security is sandboxed to the two usual smart contract security concepts: ECDSA integrity and upgradeability. In this case rogue access to TEL without bridging is infeasible unless brute forcing a private key for the RWTEL address or performing a malicious upgrade. Thus security considerations are:
  - **A.** ECDSA integrity of RWTEL (brute force its private key, probabilistically impossible)
  - **B.** Exploitation of the RWTEL module's upgradeability (steal private keys for the multisig owner)
