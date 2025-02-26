// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
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
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";

contract InterchainTokenServiceTest is Test {
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenDeployer itDeployer;
    InterchainTokenFactory itFactory;
    InterchainToken interchainTokenImpl;
    InterchainToken interchainToken; // InterchainProxy
    TokenManagerDeployer tokenManagerDeployer;
    TokenManager tokenManagerImpl;
    TokenManager tokenManager;
    TokenHandler tokenHandler;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;

    string chainName_; // "telcoin-network"

    // rwTEL constructor params
    bytes32 rwTELsalt;
    address consensusRegistry_; // currently points to TN
    address gateway_; // currently points to TN
    string name_;
    string symbol_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;

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

    address admin;
    address gasCollector;
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

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        wTEL = new WTEL();

        // deploy ITS contracts
        tokenManagerDeployer = new TokenManagerDeployer();
        //todo: deploy a tokenManager for rwTEL
        // tokenManager = tokenManagerDeployer.deployTokenManager(tokenId, implementationType, params);
        // todo: pre calculate its or tokenManager addr
        tokenManagerImpl = new TokenManager(address(its));
        itDeployer = new InterchainTokenDeployer(address(tokenManagerImpl));
        // todo: function for test deployment
        gateway_ = deployments.AxelarAmplifierGateway;
        gasService = new AxelarGasService(gasCollector);
        // note 1: deploys InterchainTokens via its; could be used to deploy eth:TEL wrapper?
        // note 2: use eth:InterchainTokenFactory.registerCanonicalInterchainToken(TEL);
        itFactory = new InterchainTokenFactory(address(its));
        chainName_ = "telcoin-network";
        tokenHandler = new TokenHandler();
        gatewayCaller = new GatewayCaller(gateway_, address(gasService));
        itsImpl = new InterchainTokenService(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway_),
            address(gasService),
            address(itFactory),
            chainName_,
            address(tokenManagerImpl),
            address(tokenHandler),
            address(gatewayCaller)
        );

        name_ = "Recoverable Wrapped Telcoin";
        symbol_ = "rwTEL";
        recoverableWindow_ = 604_800; // 1 week
        governanceAddress_ = address(this); // multisig/council/DAO address in prod
        baseERC20_ = address(wTEL);
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage
        admin = deployments.admin;

        // deploy impl + proxy and initialize
        rwTELImpl = new RWTEL{ salt: rwTELsalt }(
            address(its), name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean
        );
        rwTEL = RWTEL(payable(address(new ERC1967Proxy{ salt: rwTELsalt }(address(rwTELImpl), ""))));
        rwTEL.initialize(governanceAddress_, maxToClean, admin);
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // rwTEL sanity tests
        assertEq(rwTEL.consensusRegistry(), deployments.ConsensusRegistry);
        assertEq(address(rwTEL.interchainTokenService()), deployments.InterchainTokenService);
        assertEq(rwTEL.owner(), admin);
        assertTrue(address(rwTEL).code.length > 0);
        string memory rwName = rwTEL.name();
        assertEq(rwName, "Recoverable Wrapped Telcoin");
        string memory rwSymbol = rwTEL.symbol();
        assertEq(rwSymbol, "rwTEL");
        uint256 recoverableWindow = rwTEL.recoverableWindow();
        assertEq(recoverableWindow, 86_400);
        address governanceAddress = rwTEL.governanceAddress();
        assertEq(governanceAddress, address(this));

        // ITS sanity tests
    }

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
