/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { TokenManagerProxy } from "@axelar-network/interchain-token-service/contracts/proxies/TokenManagerProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { ITokenManager } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../../src/WTEL.sol";
import { RWTEL } from "../../src/RWTEL.sol";
import { ExtCall } from "../../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "./Create3Utils.sol";

abstract contract ITSUtils is Create3Utils {
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

    function create3DeployAxelarAmplifierGatewayImpl(Create3Deployer create3)
        public
        returns (AxelarAmplifierGateway impl)
    {
        bytes memory gatewayImplConstructorArgs =
            abi.encode(previousSignersRetention, domainSeparator, minimumRotationDelay);
        impl = AxelarAmplifierGateway(
            create3Deploy(
                create3,
                type(AxelarAmplifierGateway).creationCode,
                gatewayImplConstructorArgs,
                implSalts.gatewayImplSalt
            )
        );
    }

    function create3DeployAxelarAmplifierGateway(Create3Deployer create3, address impl)
        public
        returns (AxelarAmplifierGateway proxy)
    {
        // struct population for gateway constructor done in memory since storage structs don't work in Solidity
        WeightedSigner[] memory signerArray = new WeightedSigner[](1);
        signerArray[0] = WeightedSigner(singleSigner, weight);
        WeightedSigners memory weightedSigners = WeightedSigners(signerArray, threshold, nonce);
        WeightedSigners[] memory weightedSignersArray = new WeightedSigners[](1);
        weightedSignersArray[0] = weightedSigners;
        gatewaySetupParams = abi.encode(gatewayOperator, weightedSignersArray);
        bytes memory gatewayConstructorArgs = abi.encode(impl, gatewayOwner, gatewaySetupParams);
        proxy = AxelarAmplifierGateway(
            create3Deploy(
                create3, type(AxelarAmplifierGatewayProxy).creationCode, gatewayConstructorArgs, salts.gatewaySalt
            )
        );

        // stored for asserts only
        abiEncodedWeightedSigners = abi.encode(weightedSigners);
    }

    function create3DeployTokenManagerDeployer(Create3Deployer create3)
        public
        returns (TokenManagerDeployer tmDeployer)
    {
        tmDeployer =
            TokenManagerDeployer(create3Deploy(create3, type(TokenManagerDeployer).creationCode, "", salts.tmdSalt));
    }

    function create3DeployInterchainTokenImpl(Create3Deployer create3) public returns (InterchainToken itImpl) {
        bytes memory itImplConstructorArgs = abi.encode(precalculatedITS);
        itImpl = InterchainToken(
            create3Deploy(create3, type(InterchainToken).creationCode, itImplConstructorArgs, implSalts.itImplSalt)
        );
    }

    function create3DeployInterchainTokenDeployer(
        Create3Deployer create3,
        address interchainTokenImpl
    )
        public
        returns (InterchainTokenDeployer itd)
    {
        bytes memory itdConstructorArgs = abi.encode(interchainTokenImpl);
        itd = InterchainTokenDeployer(
            create3Deploy(create3, type(InterchainTokenDeployer).creationCode, itdConstructorArgs, salts.itdSalt)
        );
    }

    function create3DeployTokenManagerImpl(Create3Deployer create3) public returns (TokenManager tmImpl) {
        bytes memory tmConstructorArgs = abi.encode(precalculatedITS);
        tmImpl = TokenManager(
            create3Deploy(create3, type(TokenManager).creationCode, tmConstructorArgs, implSalts.tmImplSalt)
        );
    }

    function create3DeployTokenHandler(Create3Deployer create3) public returns (TokenHandler th) {
        th = TokenHandler(create3Deploy(create3, type(TokenHandler).creationCode, "", salts.thSalt));
    }

    function create3DeployAxelarGasServiceImpl(Create3Deployer create3)
        public
        returns (AxelarGasService impl)
    {
        bytes memory gsImplConstructorArgs = abi.encode(gasCollector);
        impl = AxelarGasService(
            create3Deploy(create3, type(AxelarGasService).creationCode, gsImplConstructorArgs, implSalts.gsImplSalt)
        );
    }

    function create3DeployAxelarGasService(Create3Deployer create3, address impl)
        public
        returns (AxelarGasService proxy)
    {
        bytes memory gsConstructorArgs = abi.encode(impl, gsOwner, "");
        proxy = AxelarGasService(
            create3Deploy(create3, type(AxelarGasServiceProxy).creationCode, gsConstructorArgs, salts.gsSalt)
        );
    }

    function create3DeployGatewayCaller(
        Create3Deployer create3,
        address gateway,
        address axelarGasService
    )
        public
        returns (GatewayCaller gc)
    {
        bytes memory gcConstructorArgs = abi.encode(gateway, axelarGasService);
        gc = GatewayCaller(create3Deploy(create3, type(GatewayCaller).creationCode, gcConstructorArgs, salts.gcSalt));
    }

    function create3DeployITSImpl(
        Create3Deployer create3,
        address tokenManagerDeployer,
        address itDeployer,
        address gateway,
        address gasService,
        address tokenManagerImpl,
        address tokenHandler,
        address gatewayCaller
    )
        public
        returns (InterchainTokenService impl)
    {
        bytes memory itsImplConstructorArgs = abi.encode(
            tokenManagerDeployer,
            itDeployer,
            gateway,
            gasService,
            precalculatedITFactory, // storage config
            chainName_, // storage config
            tokenManagerImpl,
            tokenHandler,
            gatewayCaller
        );
        impl = InterchainTokenService(
            create3Deploy(
                create3, type(InterchainTokenService).creationCode, itsImplConstructorArgs, implSalts.itsImplSalt
            )
        );
    }

    function create3DeployITS(
        Create3Deployer create3,
        address impl
    )
        public
        returns (InterchainTokenService proxy)
    {
        bytes memory itsConstructorArgs = abi.encode(impl, itsOwner, itsSetupParams);
        proxy = InterchainTokenService(
            create3Deploy(create3, type(InterchainProxy).creationCode, itsConstructorArgs, salts.itsSalt)
        );
    }

    function create3DeployITFImpl(
        Create3Deployer create3,
        address its
    )
        public
        returns (InterchainTokenFactory impl)
    {
        bytes memory itfImplConstructorArgs = abi.encode(its);
        impl = InterchainTokenFactory(
            create3Deploy(
                create3, type(InterchainTokenFactory).creationCode, itfImplConstructorArgs, implSalts.itfImplSalt
            )
        );
    }

    function create3DeployITF(
        Create3Deployer create3,
        address impl
    )
        public
        returns (InterchainTokenFactory proxy)
    {
        bytes memory itfConstructorArgs = abi.encode(impl, itfOwner, "");
        proxy = InterchainTokenFactory(
            create3Deploy(create3, type(InterchainProxy).creationCode, itfConstructorArgs, salts.itfSalt)
        );
    }

    /// TODO: convert to singleton for mainnet
    function create3DeployRWTELImpl(Create3Deployer create3, address its) public returns (RWTEL impl) {
        bytes memory rwTELImplConstructorArgs = abi.encode(
            canonicalTEL,
            canonicalChainName_,
            its,
            name_,
            symbol_,
            recoverableWindow_,
            governanceAddress_,
            baseERC20_,
            maxToClean
        );
        impl = RWTEL(
            payable(create3Deploy(create3, type(RWTEL).creationCode, rwTELImplConstructorArgs, implSalts.rwtelImplSalt))
        );
    }

    /// TODO: convert to singleton for mainnet
    function create3DeployRWTEL(Create3Deployer create3, address impl) public returns (RWTEL proxy) {
        bytes memory rwTELConstructorArgs = abi.encode(impl, "");
        proxy = RWTEL(
            payable(create3Deploy(create3, type(ERC1967Proxy).creationCode, rwTELConstructorArgs, salts.rwtelSalt))
        );
    }

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
        returns (bytes32 telInterchainSalt, bytes32 telInterchainTokenId, TokenManager telTokenManager)
    {
        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        service.registerTokenMetadata{ value: gasValue }(tel, gasValue);

        telInterchainSalt = factory.canonicalInterchainTokenDeploySalt(canonicalTEL);
        telInterchainTokenId = factory.registerCanonicalInterchainToken(canonicalTEL);

        telTokenManager = TokenManager(service.tokenManagerAddress(telInterchainTokenId));
    }
}
