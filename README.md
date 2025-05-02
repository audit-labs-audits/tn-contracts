# Telcoin Network Smart Contracts

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

   - **Stake:** Validators with a `ConsensusNFT` call the `stake()` function along with the required stake amount, providing their BLS public key and signature.
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

These simulations are performed by the utility in `script/GenerateConsensusRegistryGenesisConfig.s.sol`, which outputs a yaml file at `deployments/genesis/consensus-registry-config.yaml`. The canonical yaml file is then read by the protocol to include its storage configurations at genesis.

## InterchainTEL Module

### Background

Because Telcoin-Network uses Telcoin as native gas currency and Telcoin originates from Ethereum mainnet as an ERC20, solutions for nuances specific to the TN protocol have been implemented:

- Conversion between remote ERC20 TEL and TN's native gas currency as part of interchain bridging flow
- Decimals handling between remote ERC20 TEL's 2 decimals and native TEL's 18 decimals
- Ensuring native TEL is available for gas at/after Telcoin-Network genesis to perform transactions

To address the above nuances, Telcoin Network utilizes the Axelar Interchain Token Service, integrated to the protocol as system precompiles.

For the ITS precompiles to be enabled at genesis, the interchain TEL token contract and its corresponding token manager must also be system precompiles. The interchain TEL token on Telcoin-Network, called InterchainTEL, is a custom implementation handling the three points above, and its token manager, called InterchainTELTokenManager, is a standard ITS `TokenManagerProxy`.

To comply with ITS, both InterchainTEL and its accompanying `MINT_BURN` TokenManagerProxy are deployed to the Interchain Token Service's expected `create3` addresses by using the same custom-linked interchain `linkedTokenDeploySalt` and `tokenId` derived by registering Ethereum TEL as a custom interchain token.

A general overview of ITS system design can be found [in this README](src/interchain-token-service/README.md) and in Axelar's documentation.

### Design Decisions

The Interchain Telcoin (iTEL) token contract serves as Telcoin-Network's custom-linked interchain token registered under the Ethereum ERC20 TEL's interchain token ID. InterchainTEL inherits `InterchainTokenStandard` for ITS compliance as well as Circle Research's recoverable wrapper utility to enforce a timelock on bridging outbound TEL to a remote chain.

![Interchain Token Service & InterchainTEL](https://i.imgur.com/pymULlU.png)

The only way to mint native TEL on Telcoin-Network is by locking/burning TEL on a remote chain which passes a valid bridge message through ITS. The reverse is also true: the only way to bridge to remote chains from TN is by wrapping native TEL through wTEL to iTEL which is the ERC20 registered under TEL's interchain token ID.

Because InterchainTEL's token manager is of `MINT_BURN` type, delivery of inbound interchain TEL from a remote chain occurs via InterchainTEL's `mint()` function, and outbound exports of native TEL use its `burn()` function, handling decimal conversion in both cases. To understand InterchainTEL's decimals conversion between ERC20 TEL and native TEL, the ITS TokenHandler and TokenManager contracts are minimally forked to accept return parameters which are then fed to ITS: [TNTokenHandler](../TNTokenHandler) and [TNTokenManager](./TNTokenManager)

In the outbound case, ie bridging native TEL off of Telcoin-Network, TEL must first be double-wrapped to wTEL and then iTEL. For security, the InterchainTEL module enforces that only settled `RecoverableWrapper` token balances may be bridged. Only InterchainTEL balances which have awaited the module's recoverable window are considered settled, which incentivizes usage of the network and provides time-based assurance that all outbound native TEL is sourced legitimately.

#### Native TEL at Genesis

The equivalent of TEL's total supply is provided to the InterchainTEL module as native TEL at network genesis.

While the mirrored total supply of TEL native currency technically "exists" at the InterchainTEL address from network genesis, it is probabilistically inaccessible because the contract's private key cannot be brute forced and thus equivalent to being burned.
