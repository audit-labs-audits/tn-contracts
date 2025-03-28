/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";

abstract contract ITSConfig {
    // chain info
    string public ITS_HUB_CHAIN_NAME = "axelar";
    string public ITS_HUB_ROUTING_IDENTIFIER = "hub";
    string public TN_CHAIN_NAME = "telcoin-network";
    bytes32 public TN_CHAINNAMEHASH = keccak256(bytes(TN_CHAIN_NAME));
    string public MAINNET_CHAIN_NAME = "Ethereum";
    bytes32 public MAINNET_CHAINNAMEHASH = 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2;
    address public MAINNET_ITS = 0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C;
    string public DEVNET_SEPOLIA_CHAIN_NAME = "eth-sepolia";
    bytes32 public DEVNET_SEPOLIA_CHAINNAMEHASH = 0x24f78f6b35533491ef3d467d5e8306033cca94049b9b76db747dfc786df43f86;
    address public DEVNET_SEPOLIA_ITS = 0x2269B93c8D8D4AfcE9786d2940F5Fcd4386Db7ff;
    string public TESTNET_CHAIN_NAME = "ethereum-sepolia";
    bytes32 public TESTNET_CHAINNAMEHASH = 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2;
    address public TESTNET_ITS = 0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C;


    // stored assertion vars
    address precalculatedITS;
    address precalculatedITFactory;
    bytes abiEncodedWeightedSigners;

    // AxelarAmplifierGateway
    string axelarId;
    string routerAddress;
    uint256 telChainId;
    bytes32 domainSeparator;
    uint256 previousSignersRetention;
    uint256 minimumRotationDelay;
    uint128 weight;
    address singleSigner;
    uint128 threshold;
    bytes32 nonce;
    address gatewayOperator;
    bytes gatewaySetupParams;
    address gatewayOwner;

    // AxelarGasService
    address gasCollector;
    address gsOwner;
    bytes gsSetupParams;

    // InterchainTokenService
    address itsOwner;
    address itsOperator;
    string chainName_;
    string[] trustedChainNames;
    string[] trustedAddresses;
    bytes itsSetupParams;

    // InterchainTokenFactory
    address itfOwner;

    // rwTEL config
    address canonicalTEL;
    string canonicalChainName_;
    address consensusRegistry_;
    address gateway_;
    string symbol_;
    string name_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_; // wTEL
    uint16 maxToClean;


    /// todo: record contract code & storage changes for genesis
    /// @notice Registers canonical TEL with ITS hub & deploys its TokenManager on its source chain
    /// @dev After execution, relayer detects & forwards ContractCall event to Axelar Network hub via GMP API 
    /// @dev Once registered w/ ITS Hub, `msg.sender` can use same salt to register/deploy to more chains
    /// @dev TokenManagers deployed for canonical tokens have no operator; this includes canonical TEL on Ethereum
    function eth_registerCanonicalTELAndDeployTELTokenManager(
        address tel,
        InterchainTokenService service,
        InterchainTokenFactory factory,
        uint256 gasValue
    )
        public
        returns (
            bytes32 telInterchainSalt,
            bytes32 telInterchainTokenId,
            TokenManager telTokenManager
        )
    {
        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        service.registerTokenMetadata{ value: gasValue }(tel, gasValue);

        telInterchainSalt = factory.canonicalInterchainTokenDeploySalt(canonicalTEL);
        telInterchainTokenId = factory.registerCanonicalInterchainToken(canonicalTEL);

        telTokenManager = TokenManager(service.tokenManagerAddress(telInterchainTokenId));
    }
}