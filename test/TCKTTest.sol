// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import "interfaces/AvalancheTokens.sol";
import "interfaces/testing/MockTokens.sol";
import {IERC20Permit} from "interfaces/IERC20Permit.sol";
import {Signature, TCKT} from "contracts/TCKT.sol";

contract TCKTTest is Test {
    TCKT private tckt;

    function setUp() public {
        vm.prank(TCKT_DEPLOYER);
        tckt = new TCKT();
        assertEq(address(tckt), TCKT_ADDR);
    }

    function testTokenURI0() public {
        assertEq(
            tckt.tokenURI(
                0x3d5bad4604650569f28733f7ad6ec22835e775a0eb20bfd809d78ed2ae8abe47
            ),
            "https://ipfs.kimlikdao.org/ipfs/QmSUAf9gusxTbZZn5nC7d44kHjfrDeu2gfSY31MRVET28n"
        );
        assertEq(
            tckt.tokenURI(
                0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523
            ),
            "https://ipfs.kimlikdao.org/ipfs/QmcX2ScFVAVnEHrMk3xuf7HXfiGHzmMqdpAYb37zA5mbFp"
        );
    }

    function testRevoke() public {
        assertEq(tckt.balanceOf(address(this)), 0);
        tckt.create(123123123);
        assertEq(tckt.balanceOf(address(this)), 1);
        tckt.revoke();
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testSocialRevoke() public {
        tckt.createWithRevokers(
            123123123,
            [
                (uint256(4) << 192) |
                    (uint256(1) << 160) |
                    uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );

        assertEq(tckt.balanceOf(address(this)), 1);

        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(10));
        vm.expectRevert();
        tckt.revokeFriend(address(this));
        vm.prank(vm.addr(11));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(12));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(13));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testRevokeFriendForContributor() public {
        vm.prank(vm.addr(0x1337ACC));
        tckt.createWithRevokers(
            123123123,
            [
                (uint256(4) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );

        assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);

        bytes32 REVOKE_FRIEND_FOR_TYPEHASH = keccak256(
            "RevokeFriendFor(address friend)"
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(REVOKE_FRIEND_FOR_TYPEHASH, vm.addr(0x1337ACC))
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, digest);
        Signature memory sig = Signature(
            r,
            (uint256(v - 27) << 255) | uint256(s)
        );
        vm.prank(vm.addr(100));
        tckt.revokeFriendFor(vm.addr(0x1337ACC), sig);

        assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);

        vm.prank(vm.addr(11));
        tckt.revokeFriend(vm.addr(0x1337ACC));

        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testRevokeFriendFor() public {
        vm.prank(vm.addr(0x1337ACC));
        tckt.createWithRevokers(
            123123123,
            [
                (uint256(4) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );

        assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);

        vm.prank(vm.addr(11));
        tckt.revokeFriend(vm.addr(0x1337ACC));

        assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);

        bytes32 REVOKE_FRIEND_FOR_TYPEHASH = keccak256(
            "RevokeFriendFor(address friend)"
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(REVOKE_FRIEND_FOR_TYPEHASH, vm.addr(0x1337ACC))
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(10, digest);
        vm.prank(vm.addr(100));
        tckt.revokeFriendFor(
            vm.addr(0x1337ACC),
            Signature(r, (uint256(v - 27) << 255) | uint256(s))
        );

        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testLastRevokeTimePreserved() public {
        // Even someone get their private key stolen, the thief should not be
        // able to reduce the `lastRevokeTime`.
        tckt.createWithRevokers(
            1337,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                (uint256(6) << 160) | uint160(vm.addr(13)),
                (uint256(7) << 160) | uint160(vm.addr(14))
            ]
        );
        vm.expectRevert();
        tckt.reduceRevokeThreshold(8);

        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));

        assertEq(tckt.revokesRemaining(), 4);

        vm.warp(100);
        vm.prank(vm.addr(12));
        tckt.revokeFriend(address(this));

        assertEq(tckt.revokesRemaining(), 0);
        assertEq(tckt.lastRevokeTimestamp(address(this)), 100);

        vm.warp(101);
        vm.prank(vm.addr(13));
        tckt.revokeFriend(address(this));

        assertEq(tckt.revokesRemaining(), 0);
        assertGe(tckt.lastRevokeTimestamp(address(this)), 100);

        vm.warp(102);
        vm.prank(vm.addr(14));
        tckt.revokeFriend(address(this));

        assertEq(tckt.revokesRemaining(), 0);
        assertGe(tckt.lastRevokeTimestamp(address(this)), 100);

        vm.warp(103);
        tckt.createWithRevokers(
            1337,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                (uint256(6) << 160) | uint160(vm.addr(13)),
                (uint256(7) << 160) | uint160(vm.addr(14))
            ]
        );
        assertGe(tckt.lastRevokeTimestamp(address(this)), 100);
    }

    function testRevokerWeightsCannotBeDecremented() public {
        // Consider a well intentioned social revoke TCKT ...
        tckt.createWithRevokers(
            1337,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
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
        tckt.addRevoker((type(uint256).max << 160) | uint160(vm.addr(11)));

        vm.expectRevert();
        tckt.reduceRevokeThreshold(8);
    }

    function testReduceRevokeThreshold() public {
        uint256[5] memory revokers = [
            (uint256(1) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
            (uint256(1) << 160) | uint160(vm.addr(11)),
            (uint256(1) << 160) | uint160(vm.addr(12)),
            (uint256(1) << 160) | uint160(vm.addr(13)),
            (uint256(1) << 160) | uint160(vm.addr(14))
        ];
        tckt.createWithRevokers(123123123, revokers);

        assertEq(tckt.balanceOf(address(this)), 1);
        tckt.reduceRevokeThreshold(1);
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 0);

        vm.expectRevert();
        tckt.reduceRevokeThreshold(1);
    }

    function testAddRevoker() public {
        uint256[5] memory revokers = [
            (uint256(4) << 192) | (uint256(1) << 160) | uint160(vm.addr(20)),
            (uint256(1) << 160) | uint160(vm.addr(21)),
            (uint256(1) << 160) | uint160(vm.addr(12)),
            0,
            0
        ];
        tckt.createWithRevokers(123123123, revokers);

        assertEq(tckt.balanceOf(address(this)), 1);
        tckt.addRevoker((uint256(3) << 160) | uint160(vm.addr(11)));
        tckt.addRevoker((uint256(1) << 160) | uint160(vm.addr(12)));

        vm.prank(vm.addr(11));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);

        vm.prank(vm.addr(12));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testRevokesRemaining() external {
        uint256[5] memory revokers = [
            (uint256(30) << 192) | (uint256(10) << 160) | uint160(vm.addr(10)),
            (uint256(10) << 160) | uint160(vm.addr(11)),
            (uint256(10) << 160) | uint160(vm.addr(12)),
            (uint256(10) << 160) | uint160(vm.addr(13)),
            (uint256(10) << 160) | uint160(vm.addr(14))
        ];
        tckt.createWithRevokers(123123123, revokers);
        assertEq(tckt.balanceOf(address(this)), 1);
        assertEq(tckt.revokesRemaining(), 30);

        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));
        assertEq(tckt.revokesRemaining(), 20);
        assertEq(tckt.lastRevokeTimestamp(address(this)), 0);

        vm.prank(vm.addr(11));
        tckt.revokeFriend(address(this));
        assertEq(tckt.revokesRemaining(), 10);
        assertEq(tckt.lastRevokeTimestamp(address(this)), 0);

        vm.warp(1337);
        vm.prank(vm.addr(12));
        tckt.revokeFriend(address(this));
        assertEq(tckt.revokesRemaining(), 0);
        assertEq(tckt.lastRevokeTimestamp(address(this)), 1337);
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testAuthenticationPriceFeeder() public {
        vm.expectRevert();
        tckt.updatePrice((15 << 160) | uint160(vm.addr(1)));

        vm.prank(OYLAMA);
        tckt.updatePrice((15 << 160) | uint160(vm.addr(1)));
        assertEq(uint128(tckt.priceIn(vm.addr(1))), 15);

        uint256[5] memory prices = [(uint256(17) << 160) | 1337, 0, 0, 0, 0];

        vm.expectRevert();
        tckt.updatePricesBulk((1 << 128) + 1, prices);

        vm.prank(OYLAMA);
        tckt.updatePricesBulk((1 << 128) + 1, prices);
        assertEq(uint128(tckt.priceIn(address(1337))), 17);
    }

    function testUpdatePrice() public {
        vm.prank(OYLAMA);

        tckt.updatePrice((131 << 160) | uint160(vm.addr(888)));
        assertEq(uint128(tckt.priceIn(vm.addr(888))), 131);
        assertEq(tckt.priceIn(vm.addr(888)) >> 128, uint256(131 * 3) / 2);
    }

    function testUpdatePricesBulk() public {
        vm.prank(OYLAMA);
        tckt.updatePricesBulk(
            (uint256(7) << 128) | 5,
            [
                (uint256(5) << 160) | uint160(vm.addr(1)),
                (uint256(6) << 160) | uint160(vm.addr(2)),
                (uint256(7) << 160) | uint160(vm.addr(3)),
                (uint256(8) << 160) | uint160(vm.addr(4)),
                (uint256(9) << 160) | uint160(vm.addr(5))
            ]
        );

        assertEq(uint128(tckt.priceIn(vm.addr(1))), 5);
        assertEq(tckt.priceIn(vm.addr(1)) >> 128, 7);
        assertEq(uint128(tckt.priceIn(vm.addr(2))), 6);
        assertEq(tckt.priceIn(vm.addr(2)) >> 128, 8);
        assertEq(uint128(tckt.priceIn(vm.addr(3))), 7);
        assertEq(tckt.priceIn(vm.addr(3)) >> 128, 9);
        assertEq(uint128(tckt.priceIn(vm.addr(4))), 8);
        assertEq(tckt.priceIn(vm.addr(4)) >> 128, 11);
        assertEq(uint128(tckt.priceIn(vm.addr(5))), 9);
        assertEq(tckt.priceIn(vm.addr(5)) >> 128, 12);
    }

    function testCreate() public {
        vm.prank(OYLAMA);
        tckt.updatePrice(5e16 << 160);

        vm.expectRevert();
        tckt.create(123123123);

        vm.expectRevert();
        tckt.create{value: 0.04 ether}(123123123);

        vm.prank(OYLAMA);
        tckt.updatePrice(4e16 << 160);

        tckt.create{value: 0.06 ether}(1231231233);
        tckt.create{value: 0.07 ether}(123123123);

        vm.prank(OYLAMA);
        tckt.updatePrice(5e16 << 160);

        vm.expectRevert();
        tckt.create{value: 0.074 ether}(123123123);

        tckt.create{value: 0.075 ether}(1231231233);
    }

    function testUpdate() public {
        vm.expectRevert();
        tckt.update(1338);

        tckt.create(1337);
        tckt.update(1338);
    }

    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /**
     * Authorizes a payment from `vm.addr(0x1337ACC)` for the spender
     * `TCKT_ADDR`.
     */
    function authorizePayment(
        IERC20Permit token,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (Signature memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        vm.addr(0x1337ACC),
                        TCKT_ADDR,
                        amount,
                        nonce,
                        deadline
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1337ACC, digest);
        return Signature(r, (uint256(v - 27) << 255) | uint256(s));
    }

    function testUSDTPayment() public {
        DeployMockTokens();

        vm.prank(OYLAMA);
        // Set TCKT price to 2 USDT
        tckt.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        {
            uint256 deadline = block.timestamp + 1200;
            Signature memory sig = authorizePayment(USDT, 3e6, deadline, 0);

            vm.prank(vm.addr(0x1337ACC));
            uint256 deadlineAndToken = (deadline << 160) |
                uint160(address(USDT));
            tckt.createWithTokenPermit(123123123, deadlineAndToken, sig);
            assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);
        }

        vm.prank(vm.addr(0x1337ACC));
        tckt.revoke();
        {
            uint256 deadline = block.timestamp + 1200;
            Signature memory sig = authorizePayment(USDT, 3e6, deadline, 1);
            uint256 deadlineAndToken = (deadline << 160) |
                uint160(address(USDT));
            vm.prank(vm.addr(0x1337ACC));
            tckt.createWithTokenPermit(123123123, deadlineAndToken, sig);
            assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);
        }
        vm.prank(vm.addr(0x1337ACC));
        tckt.revoke();
        {
            uint256 deadline = block.timestamp + 1200;
            Signature memory sig = authorizePayment(
                USDT,
                2.999999e6,
                deadline,
                2
            );
            uint256 deadlineAndToken = (deadline << 160) |
                uint160(address(USDT));
            vm.prank(vm.addr(0x1337ACC));
            vm.expectRevert();
            tckt.createWithTokenPermit(123123123, deadlineAndToken, sig);
        }
    }

    bytes32 DOMAIN_SEPARATOR =
        0x8730afd3d29f868d9f7a9e3ec19e7635e9cf9802980a4a5c5ac0b443aea5fbd8;

    // keccak256("CreateFor(uint256 handle)")
    bytes32 CREATE_FOR_TYPEHASH =
        0xe0b70ef26ac646b5fe42b7831a9d039e8afa04a2698e03b3321e5ca3516efe70;

    function authorizeCreateFor(uint256 handle)
        public
        view
        returns (Signature memory)
    {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(CREATE_FOR_TYPEHASH, handle))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1337ACC, digest);
        return Signature(r, (uint256(v - 27) << 255) | uint256(s));
    }

    function testCreateFor() public {
        DeployMockTokens();

        vm.prank(OYLAMA);
        // Set TCKT price to 2 USDT
        tckt.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        {
            uint256 deadline = block.timestamp + 1200;
            uint256 deadlineAndToken = (deadline << 160) |
                uint160(address(USDT));
            tckt.createFor(
                123123123,
                authorizeCreateFor(123123123),
                deadlineAndToken,
                authorizePayment(
                    USDT,
                    3e6, // 2 * 1.5 for revokerless premium.
                    deadline,
                    0
                )
            );
            assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);
        }

        vm.prank(vm.addr(0x1337ACC));
        tckt.revoke();
        {
            uint256 deadline = block.timestamp + 1200;
            uint256 deadlineAndToken = (deadline << 160) |
                uint160(address(USDT));
            Signature memory createSig = authorizeCreateFor(123123123);
            Signature memory paymentSig = authorizePayment(
                USDT,
                2.99e6,
                deadline,
                0
            );
            vm.expectRevert();
            tckt.createFor(123123123, createSig, deadlineAndToken, paymentSig);
        }
    }
}
