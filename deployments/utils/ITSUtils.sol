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
import { TNTokenManager } from "../../src/interchain-token-service/TNTokenManager.sol";
import { TNTokenHandler } from "../../src/interchain-token-service/TNTokenHandler.sol";
import { Create3Utils, Salts, ImplSalts } from "./Create3Utils.sol";

abstract contract ITSUtils is Create3Utils {
    // canonical chain config for constructors, asserts (sepolia for devnet/testnet, ethereum for mainnet)
    bytes32 canonicalInterchainTokenSalt;
    bytes32 canonicalInterchainTokenId;
    TokenManager canonicalTELTokenManager;

    // ITS core contracts
    Create3Deployer create3; // not included in genesis
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    InterchainTokenDeployer itDeployer;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy
    TNTokenHandler tnTokenHandler;
    TNTokenManager tokenManagerImpl;
    TokenManager rwTELTokenManager;

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
    uint256 gasValue;
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

    // rwTELTokenManager config
    ITokenManagerType.TokenManagerType rwtelTMType;
    address tokenAddress;
    bytes operator;
    bytes params;

    // stored for assertion
    bytes abiEncodedWeightedSigners;

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

    function instantiateInterchainTokenImpl(address its_) public virtual returns (InterchainToken itImpl) {
        bytes memory itImplConstructorArgs = abi.encode(its_);
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

    function instantiateTokenManagerImpl(address its_) public virtual returns (TNTokenManager tmImpl) {
        bytes memory tmConstructorArgs = abi.encode(its_);
        tmImpl = TNTokenManager(
            create3Deploy(create3, type(TNTokenManager).creationCode, tmConstructorArgs, implSalts.tmImplSalt)
        );
    }

    function instantiateTokenHandler(bytes32 telInterchainTokenId_) public virtual returns (TNTokenHandler th) {
        bytes memory thConstructorArgs = abi.encode(telInterchainTokenId_);
        th = TNTokenHandler(create3Deploy(create3, type(TNTokenHandler).creationCode, thConstructorArgs, salts.thSalt));
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
        address itFactory_,
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
            itFactory_,
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

    function instantiateWTEL() public virtual returns (WTEL wtel) {
        wtel = WTEL(payable(create3Deploy(create3, type(WTEL).creationCode, '', salts.wtelSalt)));
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

    function instantiateRWTELTokenManager(address its_, bytes32 canonicalInterchainTokenId_) public virtual returns (TNTokenManager rwtelTM) {        
        bytes memory rwtelTMConstructorArgs = abi.encode(its_, uint256(rwtelTMType), canonicalInterchainTokenId_, params);
        rwtelTM = TNTokenManager(
            create3Deploy(create3, type(TokenManagerProxy).creationCode, rwtelTMConstructorArgs, salts.rwtelTMSalt)
        );
    }

    /// @notice Registers canonical TEL with ITS hub & deploys its TokenManager on its source chain
    /// @dev After execution, relayer detects & forwards ContractCall event to Axelar Network hub via GMP API
    /// @dev Once registered w/ ITS Hub, `msg.sender` can use same salt to register/deploy to more chains
    /// @dev TokenManagers deployed for canonical tokens like TEL on Ethereum have no operator; however
    /// TN's RWTEL TokenManager is of `NATIVE_INTERCHAIN_TOKEN` type and
    function eth_registerCanonicalTELAndDeployTELTokenManager(
        address tel,
        InterchainTokenService service,
        InterchainTokenFactory factory
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

    /// @dev Returns a single RECEIVE_FROM_HUB message for approval & execution
    function _craftITSMessage(string memory msgId, string memory srcChain, string memory srcAddress, address destAddress, bytes memory wrappedPayload) internal pure returns (Message memory) {
        bytes32 payloadHash = keccak256(wrappedPayload);
        return Message(srcChain, msgId, srcAddress, destAddress, payloadHash);
    }
}
