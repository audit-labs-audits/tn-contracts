// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RWTEL } from "../../../src/RWTEL.sol";
import { Deployments } from "../../../deployments/Deployments.sol";

/// @dev Usage: `forge script script/testnet/deploy/TestnetDeployRWTEL.s.sol \
/// --rpc-url $TN_RPC_URL -vvvv --private-key $ADMIN_PK`
// To verify RWTEL: `forge verify-contract <address> src/RWTEL.sol:RWTEL \
// --rpc-url $TN_RPC_URL --verifier sourcify --compiler-version 0.8.26 --num-of-optimizations 200`
contract TestnetDeployTokens is Script {
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    Deployments deployments;
    address admin; // admin, support, minter, burner role

    // rwTEL constructor params
    address gateway_;
    string name_;
    string symbol_;
    uint256 recoverableWindow_;
    address governanceAddress_;
    address baseERC20_;
    uint16 maxToClean;
    bytes32 rwTELsalt;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;
        rwTELsalt = keccak256("rwtel"); //todo: move to Deployments.sol
        gateway_ = deployments.AxelarAmplifierGateway;
        name_ = "Recoverable Wrapped Telcoin"; // used only for assertion
        symbol_ = "rwTEL"; // used only for assertion
        recoverableWindow_ = 604_800; // ~1 week; Telcoin Network blocktime is ~1s
        governanceAddress_ = admin; // multisig/council/DAO address in prod
        baseERC20_ = deployments.wTEL;
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage
    }

    function run() public {
        vm.startBroadcast();

        rwTELImpl = new RWTEL{ salt: rwTELsalt }(
            gateway_, name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean
        );
        rwTEL = RWTEL(payable(address(new ERC1967Proxy{ salt: rwTELsalt }(address(rwTELImpl), ""))));
        rwTEL.initialize(governanceAddress_, maxToClean, admin);

        vm.stopBroadcast();

        // asserts
        assert(rwTEL.consensusRegistry() == deployments.ConsensusRegistry);
        assert(address(rwTEL.interchainTokenService()) == deployments.InterchainTokenService);
        assert(rwTEL.baseToken() == deployments.wTEL);
        assert(rwTEL.governanceAddress() == admin);
        assert(rwTEL.recoverableWindow() == recoverableWindow_);
        assert(rwTEL.owner() == admin);
        assert(keccak256(bytes(rwTEL.name())) == keccak256(bytes(name_)));
        assert(keccak256(bytes(rwTEL.symbol())) == keccak256(bytes(symbol_)));

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/deployments/deployments.json");
        vm.writeJson(LibString.toHexString(uint256(uint160(address(rwTELImpl))), 20), dest, ".rwTELImpl");
        vm.writeJson(LibString.toHexString(uint256(uint160(address(rwTEL))), 20), dest, ".rwTEL");
    }
}
