// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import {KimlikDAOPass, Signature} from "contracts/KimlikDAOPass.sol";

contract KimlikDAOPassRevokeTest is Test {
    KimlikDAOPass private kpass;

    function setUp() public {
        vm.prank(KPASS_DEPLOYER);
        kpass = new KimlikDAOPass();
        assertEq(address(kpass), KPASS_ADDR);
    }

    function testRevoke() public {
        assertEq(kpass.balanceOf(address(this)), 0);
        kpass.create{value: 0.075 ether}(123123123);
        assertEq(kpass.balanceOf(address(this)), 1);
        kpass.revoke();
        assertEq(kpass.balanceOf(address(this)), 0);
    }

    function testSocialRevoke() public {
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(4) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );

        assertEq(kpass.balanceOf(address(this)), 1);

        vm.prank(vm.addr(10));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 1);
        vm.prank(vm.addr(10));
        vm.expectRevert();
        kpass.revokeFriend(address(this));
        vm.prank(vm.addr(11));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 1);
        vm.prank(vm.addr(12));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 1);
        vm.prank(vm.addr(13));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 0);
    }

    function testRevokeFriendForContributor() public {
        vm.deal(vm.addr(0x1337ACC), 1 ether);
        vm.prank(vm.addr(0x1337ACC));
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(4) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );

        assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);

        bytes32 REVOKE_FRIEND_FOR_TYPEHASH = keccak256("RevokeFriendFor(address friend)");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                kpass.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(REVOKE_FRIEND_FOR_TYPEHASH, vm.addr(0x1337ACC)))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, digest);
        Signature memory sig = Signature(r, (uint256(v - 27) << 255) | uint256(s));
        vm.prank(vm.addr(100));
        kpass.revokeFriendFor(vm.addr(0x1337ACC), sig);

        assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);

        vm.prank(vm.addr(11));
        kpass.revokeFriend(vm.addr(0x1337ACC));

        assertEq(kpass.balanceOf(address(this)), 0);
    }

    function testRevokeFriendFor() public {
        vm.deal(vm.addr(0x1337ACC), 1 ether);
        vm.prank(vm.addr(0x1337ACC));
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(4) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );

        assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);

        vm.prank(vm.addr(11));
        kpass.revokeFriend(vm.addr(0x1337ACC));

        assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);

        bytes32 REVOKE_FRIEND_FOR_TYPEHASH = keccak256("RevokeFriendFor(address friend)");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                kpass.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(REVOKE_FRIEND_FOR_TYPEHASH, vm.addr(0x1337ACC)))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, digest);
        vm.prank(vm.addr(100));
        kpass.revokeFriendFor(vm.addr(0x1337ACC), Signature(r, (uint256(v - 27) << 255) | uint256(s)));

        assertEq(kpass.balanceOf(address(this)), 0);
    }

    function testRevokeFriendForIntegration() external {
        vm.deal(vm.addr(1), 1 ether);
        vm.warp(11111);
        vm.prank(vm.addr(1));
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(3) << 192) | (uint256(3) << 160) | uint160(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1),
                (uint256(1) << 160) | uint160(vm.addr(2)),
                (uint256(1) << 160) | uint160(vm.addr(3)),
                (uint256(1) << 160) | uint160(vm.addr(4)),
                (uint256(1) << 160) | uint160(vm.addr(5))
            ]
        );

        assertEq(kpass.balanceOf(vm.addr(1)), 1);
        assertEq(kpass.lastRevokeTimestamp(vm.addr(1)), 0);

        vm.warp(99999);
        vm.prank(vm.addr(0xDEAD));
        kpass.revokeFriendFor(
            vm.addr(1),
            Signature(
                0xb505ca4df9f2162ed93c434d95658985478c263341e883e572e0d2b5df915d28,
                0x7626e3a897703a0f070bc496e91ffc8b6c96eb65e11d8ea6d611138d4dc27b01
            )
        );

        assertEq(kpass.balanceOf(vm.addr(1)), 0);
        assertEq(kpass.lastRevokeTimestamp(vm.addr(1)), 99999);

        vm.warp(99999 + 1);
        vm.prank(vm.addr(2));
        kpass.revokeFriend(vm.addr(1));

        assertEq(kpass.balanceOf(vm.addr(1)), 0);
        assertGe(kpass.lastRevokeTimestamp(vm.addr(1)), 99999);
    }

    function testLastRevokeTimestampPreserved() public {
        // Even someone get their private key stolen, the thief should not be
        // able to reduce the `lastRevokeTime`.
        kpass.createWithRevokers{value: 0.05 ether}(
            1337,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                (uint256(6) << 160) | uint160(vm.addr(13)),
                (uint256(7) << 160) | uint160(vm.addr(14))
            ]
        );
        vm.expectRevert();
        kpass.reduceRevokeThreshold(8);

        vm.prank(vm.addr(10));
        kpass.revokeFriend(address(this));

        assertEq(kpass.revokesRemaining(), 4);

        vm.warp(100);
        vm.prank(vm.addr(12));
        kpass.revokeFriend(address(this));

        assertEq(kpass.revokesRemaining(), 0);
        assertEq(kpass.lastRevokeTimestamp(address(this)), 100);

        vm.warp(101);
        vm.prank(vm.addr(13));
        kpass.revokeFriend(address(this));

        assertEq(kpass.revokesRemaining(), 0);
        assertGe(kpass.lastRevokeTimestamp(address(this)), 100);

        vm.warp(102);
        vm.prank(vm.addr(14));
        kpass.revokeFriend(address(this));

        assertEq(kpass.revokesRemaining(), 0);
        assertGe(kpass.lastRevokeTimestamp(address(this)), 100);

        vm.warp(103);
        kpass.createWithRevokers{value: 0.05 ether}(
            1337,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                (uint256(6) << 160) | uint160(vm.addr(13)),
                (uint256(7) << 160) | uint160(vm.addr(14))
            ]
        );
        assertGe(kpass.lastRevokeTimestamp(address(this)), 100);
    }

    function testRevokerWeightsCannotBeDecremented() public {
        // Consider a well intentioned social revoke KPASS ...
        kpass.createWithRevokers{value: 0.05 ether}(
            1337,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                (uint256(6) << 160) | uint160(vm.addr(13)),
                (uint256(7) << 160) | uint160(vm.addr(14))
            ]
        );
        // And now the private keys got compromised and the attacker
        // is trying to prevent social revokers from revoking.

        // Test for overflow cases.
        vm.expectRevert();
        kpass.addRevoker((type(uint256).max << 160) | uint160(vm.addr(11)));

        vm.expectRevert();
        kpass.reduceRevokeThreshold(8);
    }

    function testReduceRevokeThreshold() public {
        uint256[5] memory revokers = [
            (uint256(2) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
            (uint256(1) << 160) | uint160(vm.addr(11)),
            (uint256(1) << 160) | uint160(vm.addr(12)),
            (uint256(1) << 160) | uint160(vm.addr(13)),
            (uint256(1) << 160) | uint160(vm.addr(14))
        ];
        kpass.createWithRevokers{value: 0.05 ether}(123123123, revokers);

        assertEq(kpass.balanceOf(address(this)), 1);
        kpass.reduceRevokeThreshold(1);
        assertEq(kpass.balanceOf(address(this)), 1);
        vm.prank(vm.addr(10));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 0);

        vm.expectRevert();
        kpass.reduceRevokeThreshold(1);
    }

    function testAddRevoker() public {
        uint256[5] memory revokers = [
            (uint256(4) << 192) | (uint256(1) << 160) | uint160(vm.addr(20)),
            (uint256(1) << 160) | uint160(vm.addr(21)),
            (uint256(1) << 160) | uint160(vm.addr(12)),
            0,
            0
        ];
        kpass.createWithRevokers{value: 0.05 ether}(123123123, revokers);

        assertEq(kpass.balanceOf(address(this)), 1);
        kpass.addRevoker((uint256(3) << 160) | uint160(vm.addr(11)));
        kpass.addRevoker((uint256(1) << 160) | uint160(vm.addr(12)));

        vm.prank(vm.addr(11));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 1);

        vm.prank(vm.addr(12));
        kpass.revokeFriend(address(this));
        assertEq(kpass.balanceOf(address(this)), 0);
    }

    function testRevokesRemaining() external {
        uint256[5] memory revokers = [
            (uint256(30) << 192) | (uint256(10) << 160) | uint160(vm.addr(10)),
            (uint256(10) << 160) | uint160(vm.addr(11)),
            (uint256(10) << 160) | uint160(vm.addr(12)),
            (uint256(10) << 160) | uint160(vm.addr(13)),
            (uint256(10) << 160) | uint160(vm.addr(14))
        ];
        kpass.createWithRevokers{value: 0.05 ether}(123123123, revokers);
        assertEq(kpass.balanceOf(address(this)), 1);
        assertEq(kpass.revokesRemaining(), 30);
        assertEq(kpass.revokerWeight(address(this), vm.addr(10)), 10);
        assertEq(kpass.revokerWeight(address(this), vm.addr(11)), 10);
        assertEq(kpass.revokerWeight(address(this), vm.addr(12)), 10);
        assertEq(kpass.revokerWeight(address(this), vm.addr(13)), 10);

        vm.prank(vm.addr(10));
        kpass.revokeFriend(address(this));
        assertEq(kpass.revokesRemaining(), 20);
        assertEq(kpass.revokerWeight(address(this), vm.addr(10)), 0);
        assertEq(kpass.lastRevokeTimestamp(address(this)), 0);

        vm.prank(vm.addr(11));
        kpass.revokeFriend(address(this));
        assertEq(kpass.revokesRemaining(), 10);
        assertEq(kpass.lastRevokeTimestamp(address(this)), 0);

        vm.warp(1337);
        vm.prank(vm.addr(12));
        kpass.revokeFriend(address(this));
        assertEq(kpass.revokesRemaining(), 0);
        assertEq(kpass.lastRevokeTimestamp(address(this)), 1337);
        assertEq(kpass.balanceOf(address(this)), 0);
    }
}
