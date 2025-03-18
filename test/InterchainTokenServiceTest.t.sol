// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";

contract InterchainTokenServiceTest is Test {
    // TN contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    // Axelar ITS contracts
    Create3Deployer create3;
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    // InterchainToken interchainToken; // InterchainProxy //todo use deployer?
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenManager tokenManager;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy

    // shared axelar constructor params
    address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
    address deployerEOA = admin; //todo necessary?
    address precalculatedITSAddr;
    address precalculatedITF;

    // AxelarAmplifierGateway
    string axelarId = "telcoin-network"; // used as `chainName_` for ITS
    string routerAddress = "router";
    uint256 telChainId = 0x7e1;
    bytes32 domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
    uint256 previousSignersRetention = 16;
    uint256 minimumRotationDelay = 86_400; // default rotation delay is `1 day == 86400 seconds`
    uint128 weight = 1; // todo: handle additional signers
    address singleSigner = admin; // todo: increase signers
    uint128 threshold = 1; // todo: increase threshold
    bytes32 nonce = bytes32(0x0);
    // memory: weightedSignersArray = [WeightedSigners([WeightedSigner(singleSigner, weight)], threshold, nonce)];
    address gatewayOperator = admin; // todo: separate operator
    bytes gatewaySetupParams; // = abi.encode(gatewayOperator, weightedSignersArray);
    address gatewayOwner = admin; // todo: separate owner

    // AxelarGasService
    address gasCollector = address(0xc011ec106);
    address gsOwner = admin;
    bytes gsSetupParams = ""; // unused

    // InterchainTokenService
    address itsOwner = admin; // todo: separate owner
    address itsOperator = admin; // todo: separate operator
    string chainName_ = axelarId;
    string[] trustedChainNames = [chainName_]; //todo: change to supported chains
    string[] trustedAddresses = [Strings.toString(uint256(uint160(admin)))]; //todo: change to remote ITS hub(s)
    bytes itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

    // rwTEL config
    address consensusRegistry_; // currently points to TN
    address gateway_; // currently points to TN
    string symbol_ = "rwTEL";
    string name_ = "Recoverable Wrapped Telcoin";
    uint256 recoverableWindow_ = 604_800; // todo: confirm 1 week
    address governanceAddress_ = address(0xda0); // todo: multisig/council/DAO address in prod
    address baseERC20_ = address(wTEL);
    uint16 maxToClean = type(uint16).max; // todo: revisit gas expectations; clear all relevant storage?
    address rwtelOwner = admin; //todo: separate owner, multisig?

    //todo: move these to Deployments.sol
    bytes32 agsSalt = keccak256("axelar-gas-service");
    bytes32 create3Salt = keccak256("create3-deployer");
    bytes32 gatewayImplSalt = keccak256("axelar-amplifier-gateway-impl");
    bytes32 gatewaySalt = keccak256("axelar-amplifier-gateway");
    bytes32 gcSalt = keccak256("gateway-caller");
    bytes32 gsImplSalt = keccak256("axelar-gas-service-impl");
    bytes32 gsSalt = keccak256("axelar-gas-service");
    bytes32 itImplSalt= keccak256("interchain-token-impl");
    bytes32 itdSalt = keccak256("interchain-token-deployer");
    bytes32 itfImplSalt = keccak256("interchain-token-factory-impl");
    bytes32 itfSalt = keccak256("interchain-token-factory");
    bytes32 itsImplSalt = keccak256("interchain-token-service-impl");
    bytes32 itsSalt = keccak256("interchain-token-service");
    bytes32 thSalt = keccak256("token-handler");
    bytes32 tmImplSalt = keccak256("token-manager-impl");
    bytes32 tmSalt = keccak256("token-manager");
    bytes32 tmdSalt = keccak256("token-manager-deployer");
    bytes32 rwtelImplSalt = keccak256("rwtel-impl");
    bytes32 rwtelSalt = keccak256("rwtel");

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin; // used for all CREATE3 deployments
        wTEL = new WTEL();

        // note: CREATE3 contract deployed via `create2`
        create3 = new Create3Deployer{ salt: create3Salt }();
        // deploy ITS contracts via `CREATE3` as `sender == deployerEOA` for predictability & stability
        vm.startPrank(deployerEOA);
        (gatewayImpl, gateway) = deployAxelarAmplifierGateway(create3, gatewayImplSalt, gatewaySalt);

        tokenManagerDeployer = TokenManagerDeployer(deployContract(create3, type(TokenManagerDeployer).creationCode, '', tmdSalt));

        // ITS address has no code yet but must be precalculated for TokenManager && InterchainToken constructors using correct sender & salt
        precalculatedITSAddr = create3.deployedAddress("", deployerEOA, itsSalt);
        bytes memory itImplConstructorArgs = abi.encode(precalculatedITSAddr);
        interchainTokenImpl = InterchainToken(deployContract(create3, type(InterchainToken).creationCode, itImplConstructorArgs, itImplSalt));

        bytes memory itdConstructorArgs = abi.encode(address(interchainTokenImpl));
        itDeployer = InterchainTokenDeployer(
            deployContract(create3, type(InterchainTokenDeployer).creationCode, itdConstructorArgs, itdSalt)
        );

        bytes memory tmConstructorArgs = abi.encode(precalculatedITSAddr);
        tokenManagerImpl = TokenManager(
            deployContract(create3, type(TokenManager).creationCode, tmConstructorArgs, tmImplSalt)
        );

        tokenHandler = TokenHandler(deployContract(create3, type(TokenHandler).creationCode, '', thSalt));
        // todo: postTokenManagerDeploy() seems odd 

        //todo: deploy a tokenManager for rwTEL -- should this call go through ITS vs tdDeployer contract? adds
        // permissioning?
        // tokenManager = tokenManagerDeployer.deployTokenManager(tokenId, implementationType, params);
        //todo: deploy interchainToken via create3 or via ITS? not necessary for teL?

        bytes memory gsImplConstructorArgs = abi.encode(gasCollector);
        gasServiceImpl = AxelarGasService(deployContract(create3, type(AxelarGasService).creationCode, gsImplConstructorArgs, gsImplSalt));
        bytes memory gsConstructorArgs = abi.encode(address(gasServiceImpl), gsOwner, '');
        gasService = AxelarGasService(deployContract(create3, type(AxelarGasServiceProxy).creationCode, gsConstructorArgs, gsSalt));

        bytes memory gcConstructorArgs = abi.encode(address(gateway), address(gasService));
        gatewayCaller = GatewayCaller(deployContract(create3, type(GatewayCaller).creationCode, gcConstructorArgs, gcSalt));

        // must precalculate to avoid `ITS::constructor()` revert
        //todo itfSalt?
        precalculatedITF = create3.deployedAddress("", address(deployerEOA), itfImplSalt);

        bytes memory itsImplConstructorArgs = abi.encode(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            precalculatedITF,
            chainName_,
            address(tokenManagerImpl),
            address(tokenHandler),
            address(gatewayCaller)
        );
        itsImpl = InterchainTokenService(deployContract(create3, type(InterchainTokenService).creationCode, itsImplConstructorArgs, itsImplSalt));
        // new InterchainTokenService(
        //     address(tokenManagerDeployer),
        //     address(itDeployer),
        //     address(gateway),
        //     address(gasService),
        //     precalculatedITF,//address(itFactory), todo
        //     chainName_,
        //     address(tokenManagerImpl),
        //     address(tokenHandler),
        //     address(gatewayCaller)
        // );

        bytes memory itsConstructorArgs = abi.encode(address(itsImpl), itsOwner, itsSetupParams);
        its = InterchainTokenService(
            deployContract(create3, type(InterchainProxy).creationCode, itsConstructorArgs, itsSalt)
        );

        vm.stopPrank();

        // sanity check create3 precalculation
        assertEq(precalculatedITSAddr, address(its));

        // todo: ITF impl & proxy
        // itFactoryImpl = new InterchainTokenFactory(address(its));
        // assertEq(precalculatedITF, address(itf));

        // deploy impl + proxy and initialize
        // rwTELImpl = new RWTEL{ salt: rwtelSalt } //todo
        // rwTEL = RWTEL(payable(address(new ERC1967Proxy{ salt: rwtelSalt }(address(rwTELImpl), ""))));

        //todo: incorporate RWTEL contracts to TN protocol on rust side
        bytes memory rwTELImplConstructorArgs = abi.encode(
            address(its), name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean
        );
        rwTELImpl = RWTEL(payable(deployContract(create3, type(RWTEL).creationCode, rwTELImplConstructorArgs, rwtelImplSalt)));

        // todo: InterchainProxy?
        bytes memory rwTELConstructorArgs = abi.encode(address(rwTELImpl), "");
        rwTEL = RWTEL(payable(deployContract(create3, type(ERC1967Proxy).creationCode, rwTELConstructorArgs, rwtelSalt)));

        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // gateway sanity tests
        assertEq(gateway.owner(), gatewayOwner);
        assertEq(gateway.implementation(), address(gatewayImpl));
        assertEq(gateway.contractId(), gatewaySalt);
        assertEq(gateway.operator(), gatewayOperator);
        assertEq(gateway.previousSignersRetention(), previousSignersRetention);
        assertEq(gateway.domainSeparator(), domainSeparator);
        assertEq(gateway.minimumRotationDelay(), minimumRotationDelay);

        // ITS sanity tests
        assertEq(interchainTokenImpl.interchainTokenService(), address(its));
        assertEq(itDeployer.implementationAddress(), address(interchainTokenImpl));
        assertEq(tokenManagerImpl.interchainTokenService(), address(its));
        assertEq(gasService.implementation(), address(gasServiceImpl));
        assertEq(gasService.gasCollector(), gasCollector);
        assertEq(gasService.contractId(), gsSalt);
        assertEq(address(gatewayCaller.gateway()), address(gateway));
        assertEq(address(gatewayCaller.gasService()), address(gasService));

        // immutables set in bytecode can be checked on impl
        assertEq(itsImpl.tokenManagerDeployer(), address(tokenManagerDeployer));
        assertEq(itsImpl.interchainTokenDeployer(), address(itDeployer));
        assertEq(address(itsImpl.gateway()), address(gateway));
        assertEq(address(itsImpl.gasService()), address(gasService));
        assertEq(itsImpl.interchainTokenFactory(), precalculatedITF); //todo: address(itf)
        assertEq(itsImpl.chainNameHash(), keccak256(bytes(chainName_)));
        assertEq(itsImpl.tokenManager(), address(tokenManagerImpl));
        assertEq(itsImpl.tokenHandler(), address(tokenHandler));
        assertEq(itsImpl.gatewayCaller(), address(gatewayCaller));
        assertEq(itsImpl.tokenManagerImplementation(0), address(tokenManagerImpl));
       
        //todo: ITS asserts (requires registration, deployed rwtelTokenManager)
        // assertEq(its.tokenManagerAddress(tokenId), address(rwtelTokenManager));
        // assertEq(its.deployedTokenManager(tokenId), rwtelTokenManager);
        // assertEq(its.registeredTokenAddress(tokenId), address(rwtel));
        // assertEq(its.interchainTokenAddress(tokenId), address(rwtel));
        // assertEq(its.interchainTokenId(deployerEOA, rwtelSalt), rwtelTokenId);
        assertEq(its.tokenManagerImplementation(0), address(tokenManagerImpl));
        // assertEq(its.getExpressExecutor(commandId, sourceChain, sourceAddress, payloadHash), address(expressExecutor));


        // //todo: InterchainToken asserts; RWTEL is InterchainToken?
        // assertEq(interchainToken.interchainTokenService(), address(its));
        // assertTrue(interchainToken.isMinter(address(its)));
        // assertEq(interchainToken.totalSupply(), totalSupply);
        // assertEq(interchainToken.balanceOf(address(rwTEL)), bal);
        // assertEq(interchainToken.nameHash(), nameHash);
        // assertEq(interchainToken.DOMAIN_SEPARATOR(), itDomainSeparator);

        // todo: update for protocol integration on rust side 
        // rwTEL sanity tests
        assertEq(rwTEL.consensusRegistry(), deployments.ConsensusRegistry);
        assertEq(address(rwTEL.interchainTokenService()), address(its)); // todo: deployments.InterchainTokenService);
        assertEq(rwTEL.owner(), rwtelOwner);
        assertTrue(address(rwTEL).code.length > 0);
        assertEq(rwTEL.name(), name_);
        assertEq(rwTEL.symbol(), symbol_);
        assertEq(rwTEL.recoverableWindow(), recoverableWindow_);
        assertEq(rwTEL.governanceAddress(), governanceAddress_);

        // //todo: RWTEL TokenManager asserts
        // assertEq(tokenManager.isOperator(operator), true);
        // assertEq(tokenManager.isFlowLimiter(flowLimiter), true);
        // assertEq(tokenManager.flowLimits(), correct); // set by ITS
        // assertEq(tokenManager.getTokenAddressFromParams(tmSetupParams), address(token));
    }

    // function test_ITS() public {
    //     its.registerTokenMetadata(address(rwtel), gasValue);
    //     its.registerCustomToken(rwtelSalt, address(rwtel), type, linkParams);
    //     its.linkToken(rwtelSalt, destChain, destAddress, type, linkParams, gasValue);
    //     its.contractCallValue(); // todo: decimals handling?
    // }

    // todo: move to separate file

    /// @dev Deploys a contract using `CREATE3`
    function deployContract(
        Create3Deployer create3Deployer,
        bytes memory contractCreationCode,
        bytes memory constructorArgs,
        bytes32 salt
    ) public returns (address deployment) {
        bytes memory contractInitCode = bytes.concat(
            contractCreationCode,
            constructorArgs
        );
        return create3Deployer.deploy(contractInitCode, salt);
    }

    function deployAxelarAmplifierGateway(
        Create3Deployer create3Deployer,
        bytes32 implSalt,
        bytes32 proxySalt
    )
        public
        returns (AxelarAmplifierGateway, AxelarAmplifierGateway)
    {
        // construct contract init code for gateway impl
        bytes memory gatewayImplInitcode = bytes.concat(
            type(AxelarAmplifierGateway).creationCode,
            abi.encode(previousSignersRetention, domainSeparator, minimumRotationDelay)
        );

        gatewayImpl = AxelarAmplifierGateway(create3Deployer.deploy(gatewayImplInitcode, gatewayImplSalt));

        // must be done in memory since structs can't be written to storage in Solidity
        WeightedSigner[] memory signerArray = new WeightedSigner[](1);
        signerArray[0] = WeightedSigner(singleSigner, weight);
        WeightedSigners memory weightedSigners = WeightedSigners(signerArray, threshold, nonce);
        WeightedSigners[] memory weightedSignersArray = new WeightedSigners[](1);
        weightedSignersArray[0] = weightedSigners;
        // construct contract init code for gateway proxy
        gatewaySetupParams = abi.encode(gatewayOperator, weightedSignersArray);
        bytes memory gatewayProxyInitcode = bytes.concat(
            type(AxelarAmplifierGatewayProxy).creationCode,
            abi.encode(address(gatewayImpl), gatewayOwner, gatewaySetupParams)
        );

        gateway = AxelarAmplifierGateway(create3Deployer.deploy(gatewayProxyInitcode, proxySalt));

        return (gatewayImpl, gateway);
    }

    // todo: move to separate file
    // for fork tests
    Deployments deployments;

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    // todo: using duplicate gateway until Axelar registers TEL to canonical gateway
    IAxelarGateway sepoliaGateway;
    IERC20 sepoliaTel;
    AxelarAmplifierGateway tnGateway;
    WTEL tnWTEL;
    RWTEL tnRWTEL;

    address user;
    string sourceChain;
    string sourceAddress;
    string destChain;
    string destAddress;
    string symbol;
    uint256 amount;
    bytes extCallData;
    bytes payload;
    bytes32 payloadHash;
    string messageId;
    Message[] messages;

    function setUpForkConfig() internal {
        // todo: currently replica; change to canonical Axelar sepolia gateway
        sepoliaGateway = IAxelarGateway(0xB906fC799C9E51f1231f37B867eEd1d9C5a6D472);
        sepoliaTel = IERC20(deployments.sepoliaTEL);
        tnGateway = AxelarAmplifierGateway(deployments.AxelarAmplifierGateway);
        tnWTEL = WTEL(payable(deployments.wTEL));
        tnRWTEL = RWTEL(payable(deployments.rwTEL));

        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
        symbol = "TEL";
        amount = 100; // 1 tel

        //todo: deploy ITS contracts for fork testing
    }

    function test_bridgeSimulationSepoliaToTN() public {
        //todo
    }
}
