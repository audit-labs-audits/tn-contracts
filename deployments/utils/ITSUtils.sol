/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
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
import { ITS } from "../Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "./Create3Utils.sol";

abstract contract ITSUtils is Create3Utils {
    // ITS core contracts
    Create3Deployer create3; // not included in genesis
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy
    TokenManager canonicalRWTELTokenManager;

    // Telcoin Network contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;
    address rwtelOwner; // note: devnet only

    // AxelarAmplifierGateway config
    string axelarId;
    string routerAddress;
    uint256 telChainId;
    bytes32 domainSeparator;
    uint256 previousSignersRetention;
    uint256 minimumRotationDelay;
    uint128 weight;
    uint128 threshold;
    bytes32 nonce;
    address[] ampdVerifierSigners;
    WeightedSigner[] signerArray;
    address gatewayOperator;
    bytes gatewaySetupParams;
    address gatewayOwner;

    // AxelarGasService config
    address gasCollector;
    address gsOwner;
    bytes gsSetupParams;

    // InterchainTokenService config
    address itsOwner;
    address itsOperator;
    string chainName_;
    string[] trustedChainNames;
    string[] trustedAddresses;
    bytes itsSetupParams;

    // InterchainTokenFactory config
    address itfOwner;

    // rwTEL config
    address canonicalTEL;
    string canonicalChainName_;
    string symbol_;
    string name_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_; // wTEL
    uint16 maxToClean;

    // stored vars for assertion
    address precalculatedITS;
    address precalculatedITFactory;
    bytes abiEncodedWeightedSigners;

    // expose the message type constants that serve as headers for ITS messages between chains
    uint256 internal constant MESSAGE_TYPE_INTERCHAIN_TRANSFER = 0;
    uint256 internal constant MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN = 1;
    // uint256 internal constant MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER = 2;
    uint256 internal constant MESSAGE_TYPE_SEND_TO_HUB = 3;
    uint256 internal constant MESSAGE_TYPE_RECEIVE_FROM_HUB = 4;
    uint256 internal constant MESSAGE_TYPE_LINK_TOKEN = 5;
    uint256 internal constant MESSAGE_TYPE_REGISTER_TOKEN_METADATA = 6;

    /// @notice Instantiation functions
    /// @notice All ITSUtils default implementations use CREATE3 a la ITS
    /// @dev Overrides such as the genesis impls in GenerateITSGenesisConfig may differ (eg cheat codes)

    function instantiateAxelarAmplifierGatewayImpl()
        public virtual
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

    function instantiateAxelarAmplifierGateway(address impl)
        public virtual
        returns (AxelarAmplifierGateway proxy)
    {        
        bytes memory gatewayConstructorArgs = abi.encode(impl, gatewayOwner, gatewaySetupParams);
        proxy = AxelarAmplifierGateway(
            create3Deploy(
                create3, type(AxelarAmplifierGatewayProxy).creationCode, gatewayConstructorArgs, salts.gatewaySalt
            )
        );
    }

    function instantiateTokenManagerDeployer()
        public virtual
        returns (TokenManagerDeployer tmDeployer)
    {
        tmDeployer =
            TokenManagerDeployer(create3Deploy(create3, type(TokenManagerDeployer).creationCode, "", salts.tmdSalt));
    }

    function instantiateInterchainTokenImpl() public virtual returns (InterchainToken itImpl) {
        bytes memory itImplConstructorArgs = abi.encode(precalculatedITS);
        itImpl = InterchainToken(
            create3Deploy(create3, type(InterchainToken).creationCode, itImplConstructorArgs, implSalts.itImplSalt)
        );
    }

    function instantiateInterchainTokenDeployer(
        
        address interchainTokenImpl_
    )
        public virtual
        returns (InterchainTokenDeployer itd)
    {
        bytes memory itdConstructorArgs = abi.encode(interchainTokenImpl_);
        itd = InterchainTokenDeployer(
            create3Deploy(create3, type(InterchainTokenDeployer).creationCode, itdConstructorArgs, salts.itdSalt)
        );
    }

    function instantiateTokenManagerImpl() public virtual returns (TokenManager tmImpl) {
        bytes memory tmConstructorArgs = abi.encode(precalculatedITS);
        tmImpl = TokenManager(
            create3Deploy(create3, type(TokenManager).creationCode, tmConstructorArgs, implSalts.tmImplSalt)
        );
    }

    function instantiateTokenHandler() public virtual returns (TokenHandler th) {
        th = TokenHandler(create3Deploy(create3, type(TokenHandler).creationCode, "", salts.thSalt));
    }

    function instantiateAxelarGasServiceImpl()
        public virtual
        returns (AxelarGasService impl)
    {
        bytes memory gsImplConstructorArgs = abi.encode(gasCollector);
        impl = AxelarGasService(
            create3Deploy(create3, type(AxelarGasService).creationCode, gsImplConstructorArgs, implSalts.gsImplSalt)
        );
    }

    function instantiateAxelarGasService(address impl)
        public virtual
        returns (AxelarGasService proxy)
    {
        bytes memory gsConstructorArgs = abi.encode(impl, gsOwner, "");
        proxy = AxelarGasService(
            create3Deploy(create3, type(AxelarGasServiceProxy).creationCode, gsConstructorArgs, salts.gsSalt)
        );
    }

    function instantiateGatewayCaller(
        
        address gateway_,
        address axelarGasService_
    )
        public virtual
        returns (GatewayCaller gc)
    {
        bytes memory gcConstructorArgs = abi.encode(gateway_, axelarGasService_);
        gc = GatewayCaller(create3Deploy(create3, type(GatewayCaller).creationCode, gcConstructorArgs, salts.gcSalt));
    }

    function instantiateITSImpl(
        address tokenManagerDeployer_,
        address itDeployer_,
        address gateway_,
        address gasService_,
        address tokenManagerImpl_,
        address tokenHandler_,
        address gatewayCaller_
    )
        public virtual
        returns (InterchainTokenService impl)
    {
        bytes memory itsImplConstructorArgs = abi.encode(
            tokenManagerDeployer_,
            itDeployer_,
            gateway_,
            gasService_,
            precalculatedITFactory, // storage config
            chainName_, // storage config
            tokenManagerImpl_,
            tokenHandler_,
            gatewayCaller_
        );
        impl = InterchainTokenService(
            create3Deploy(
                create3, type(InterchainTokenService).creationCode, itsImplConstructorArgs, implSalts.itsImplSalt
            )
        );
    }

    function instantiateITS(
        address impl
    )
        public virtual
        returns (InterchainTokenService proxy)
    {
        bytes memory itsConstructorArgs = abi.encode(impl, itsOwner, itsSetupParams);
        proxy = InterchainTokenService(
            create3Deploy(create3, type(InterchainProxy).creationCode, itsConstructorArgs, salts.itsSalt)
        );
    }

    function instantiateITFImpl(
        address its_
    )
        public virtual
        returns (InterchainTokenFactory impl)
    {
        bytes memory itfImplConstructorArgs = abi.encode(its_);
        impl = InterchainTokenFactory(
            create3Deploy(
                create3, type(InterchainTokenFactory).creationCode, itfImplConstructorArgs, implSalts.itfImplSalt
            )
        );
    }

    function instantiateITF(
        address impl
    )
        public virtual
        returns (InterchainTokenFactory proxy)
    {
        bytes memory itfConstructorArgs = abi.encode(impl, itfOwner, "");
        proxy = InterchainTokenFactory(
            create3Deploy(create3, type(InterchainProxy).creationCode, itfConstructorArgs, salts.itfSalt)
        );
    }

    /// TODO: convert to singleton for mainnet
    function instantiateRWTELImpl(address its_) public virtual returns (RWTEL impl) {
        bytes memory rwTELImplConstructorArgs = abi.encode(
            canonicalTEL,
            canonicalChainName_,
            its_,
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
    function instantiateRWTEL(address impl) public virtual returns (RWTEL proxy) {
        bytes memory rwTELConstructorArgs = abi.encode(impl, "");
        proxy = RWTEL(
            payable(create3Deploy(create3, type(ERC1967Proxy).creationCode, rwTELConstructorArgs, salts.rwtelSalt))
        );
    }

    /// @dev Sets this contract's state using ITS fetched from a `deployments.json` file
    function _setGenesisTargets(ITS memory genesisITSTargets, address rwtelImpl, address rwtel) internal {
        gatewayImpl = AxelarAmplifierGateway(genesisITSTargets.AxelarAmplifierGatewayImpl);
        gateway = AxelarAmplifierGateway(genesisITSTargets.AxelarAmplifierGateway);
        tokenManagerDeployer = TokenManagerDeployer(genesisITSTargets.TokenManagerDeployer);
        interchainTokenImpl = InterchainToken(genesisITSTargets.InterchainTokenImpl);
        itDeployer = InterchainTokenDeployer(genesisITSTargets.InterchainTokenDeployer);
        tokenManagerImpl = TokenManager(genesisITSTargets.TokenManagerImpl);
        tokenHandler = TokenHandler(genesisITSTargets.TokenHandler);
        gasServiceImpl = AxelarGasService(genesisITSTargets.GasServiceImpl);
        gasService = AxelarGasService(genesisITSTargets.GasService);
        gatewayCaller = GatewayCaller(genesisITSTargets.GatewayCaller);
        itsImpl = InterchainTokenService(genesisITSTargets.InterchainTokenServiceImpl);
        its = InterchainTokenService(genesisITSTargets.InterchainTokenService);
        itFactoryImpl = InterchainTokenFactory(genesisITSTargets.InterchainTokenFactoryImpl);
        itFactory = InterchainTokenFactory(genesisITSTargets.InterchainTokenFactory);
        rwTELImpl = RWTEL(rwtelImpl);
        rwTEL = RWTEL(rwtel);
        //todo: add canonicalTELTokenManager (which will be same as RWTELTokenManager)
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

    /// @dev Returns a single ITS message crafted with the given parameters
    function _craftITSMessage(string memory msgId, string memory srcChain, string memory srcAddress, address destAddress, bytes memory msgPayload) internal pure returns (Message memory) {
        bytes32 payloadHash = keccak256(msgPayload);
        return Message(srcChain, msgId, srcAddress, destAddress, payloadHash);
    }

    /// @dev Returns the gateway's WeightedSigners and messages hash, which if signed by enough ampd verifiers
    /// will approve them for execution. Ampd verifiers sign only if their NVV includes the messages in a finalized block 
    /// @notice The returned hash for ampd verifier signing is `eth_sign` prefixed
    function _getWeightedSignersAndApproveMessagesHash(Message[] memory msgs, AxelarAmplifierGateway destinationGateway) internal view returns (WeightedSigners memory, bytes32) {
        WeightedSigners memory signers = WeightedSigners(signerArray, threshold, nonce);

        // proof must be signed keccak hash of abi encoded `CommandType.ApproveMessages` & message array
        bytes32 dataHash = keccak256(abi.encode(CommandType.ApproveMessages, msgs));
        // `domainSeparator` and `signersHash` for the current epoch are queriable on gateway
        bytes32 ethSignApproveMsgsHash = keccak256(
            bytes.concat(
                "\x19Ethereum Signed Message:\n96",
                destinationGateway.domainSeparator(),
                destinationGateway.signersHashByEpoch(destinationGateway.epoch()),
                dataHash
            )
        );

        return (signers, ethSignApproveMsgsHash);
    }
}
