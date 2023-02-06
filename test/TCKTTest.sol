// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import "interfaces/AvalancheTokens.sol";
import "interfaces/testing/MockTokens.sol";
import {IERC165} from "interfaces/IERC165.sol";
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
                tckt.DOMAIN_SEPARATOR(),
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
                tckt.DOMAIN_SEPARATOR(),
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

    function testRevokeFriendForIntegration() external {
        vm.warp(11111);
        vm.prank(vm.addr(1));
        tckt.createWithRevokers(
            123123123,
            [
                (uint256(3) << 192) |
                    (uint256(3) << 160) |
                    uint160(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1),
                (uint256(1) << 160) | uint160(vm.addr(2)),
                (uint256(1) << 160) | uint160(vm.addr(3)),
                (uint256(1) << 160) | uint160(vm.addr(4)),
                (uint256(1) << 160) | uint160(vm.addr(5))
            ]
        );

        assertEq(tckt.balanceOf(vm.addr(1)), 1);
        assertEq(tckt.lastRevokeTimestamp(vm.addr(1)), 0);

        vm.warp(99999);
        vm.prank(vm.addr(0xDEAD));
        tckt.revokeFriendFor(
            vm.addr(1),
            Signature(
                0x42e3139736e2b64a55ea99272ef446b6cc9b2bc7c9dbd28f00ffee7355685c37,
                0xb798665eec9092093ae3f9ebf66aa26ff8b999b440b2b95279f16bf6a0383f19
            )
        );

        assertEq(tckt.balanceOf(vm.addr(1)), 0);
        assertEq(tckt.lastRevokeTimestamp(vm.addr(1)), 99999);

        vm.warp(99999 + 1);
        vm.prank(vm.addr(2));
        tckt.revokeFriend(vm.addr(1));

        assertEq(tckt.balanceOf(vm.addr(1)), 0);
        assertGe(tckt.lastRevokeTimestamp(vm.addr(1)), 99999);
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
        assertEq(tckt.revokerWeight(address(this), vm.addr(10)), 10);
        assertEq(tckt.revokerWeight(address(this), vm.addr(11)), 10);
        assertEq(tckt.revokerWeight(address(this), vm.addr(12)), 10);
        assertEq(tckt.revokerWeight(address(this), vm.addr(13)), 10);

        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));
        assertEq(tckt.revokesRemaining(), 20);
        assertEq(tckt.revokerWeight(address(this), vm.addr(10)), 0);
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

    function testUnsupportedTokenPayment() external {
        DeployMockTokens();
        vm.prank(OYLAMA);
        // Set TCKT price to 4 YUSD
        tckt.updatePrice((4e6 << 160) | uint160(address(YUSD)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        uint256 deadline = block.timestamp + 1200;
        Signature memory sig = authorizePayment(USDT, 6e6, deadline, 0);

        vm.prank(vm.addr(0x1337ACC));
        uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
        vm.expectRevert();
        tckt.createWithTokenPermit(123123123, deadlineAndToken, sig);
    }

    function testInvalidSpendSignature() external {
        DeployMockTokens();
        vm.prank(OYLAMA);
        // Set TCKT price to 4 YUSD
        tckt.updatePrice((4e6 << 160) | uint160(address(YUSD)));

        vm.prank(YUSD_DEPLOYER);
        YUSD.transfer(vm.addr(0x1337ACC), 15e6);

        uint256 deadline = block.timestamp + 1200;
        Signature memory sig = authorizePayment(YUSD, 6e6, deadline, 0);
        // Break the signature
        sig.yParityAndS -= 1;

        vm.prank(vm.addr(0x1337ACC));
        uint256 deadlineAndToken = (deadline << 160) | uint160(address(YUSD));
        vm.expectRevert();
        tckt.createWithTokenPermit(123123123, deadlineAndToken, sig);
    }

    function testApproveAndCreate() external {
        DeployMockTokens();

        vm.prank(OYLAMA);
        // Set TCKT price to 2 USDT
        tckt.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 10e6);

        vm.startPrank(vm.addr(0x1337ACC));
        USDT.approve(address(tckt), 1e6);
        vm.expectRevert();
        tckt.createWithRevokersWithTokenPayment(
            123123123,
            [
                (uint256(1) << 192) |
                    (uint256(1) << 160) |
                    uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ],
            USDT
        );

        USDT.approve(address(tckt), 2e6);
        tckt.createWithRevokersWithTokenPayment(
            123123123,
            [
                (uint256(1) << 192) |
                    (uint256(1) << 160) |
                    uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ],
            USDT
        );

        assertEq(tckt.balanceOf(vm.addr(0x1337ACC)), 1);
        assertEq(USDT.balanceOf(vm.addr(0x1337ACC)), 8e6);

        USDT.approve(address(tckt), 2e6);
        vm.expectRevert();
        tckt.createWithTokenPayment(123123123, USDT);

        USDT.approve(address(tckt), 3e6);
        tckt.createWithTokenPayment(123123123, USDT);
    }

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
                tckt.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(CREATE_FOR_TYPEHASH, handle))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1337ACC, digest);
        return Signature(r, (uint256(v - 27) << 255) | uint256(s));
    }

    function testCreateFor() public {
        DeployMockTokens();

        vm.deal(OYLAMA, 100000);
        vm.prank(OYLAMA);
        // Set TCKT price to 2 USDT
        tckt.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        {
            uint256 deadline = block.timestamp + 1200;
            uint256 deadlineAndToken = (deadline << 160) |
                uint160(address(USDT));
            vm.startPrank(OYLAMA);
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
            vm.stopPrank();

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
            vm.prank(OYLAMA);
            tckt.createFor(123123123, createSig, deadlineAndToken, paymentSig);
        }
    }

    function testCreateForIntegration() external {
        DeployMockTokens();

        // `OYLAMA` mints a TCKT on behalf of
        // 0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1.
        // The handle is 0x7A4D1E and the TCKT costs 3 USDC.

        vm.prank(OYLAMA);
        // Set TCKT price to 2 USDC
        tckt.updatePrice((2e6 << 160) | uint160(address(USDC)));

        vm.prank(USDC_DEPLOYER);
        USDC.transfer(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1, 3e6);

        assertEq(tckt.balanceOf(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1), 0);

        // Give some gas money to OYLAMA.
        vm.deal(OYLAMA, 10000000);
        vm.startPrank(OYLAMA);
        tckt.createFor(
            0x7A4D1E,
            Signature(
                0xfe70b2e6399ca3301ab720f81d92494052a3cbc42e6a820d127b961d2f077d10,
                0xa2e0a6583fdbec6060db018606d652c7d2e3e5da56b5da54977d43d6471363ef
            ),
            (uint256(123456) << 160) | uint160(address(USDC)),
            Signature(
                0x0c85fb2045ea50c34e54e4a0df7648ba9181bd0903083366cf34958aaabf4a78,
                0x0a15c9164d7c60c4cb1aa37879090cc83c78888e66e3d41663919e38006648ef
            )
        );
        vm.stopPrank();

        assertEq(tckt.balanceOf(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1), 1);
    }

    function testTypeHashes() external {
        assertEq(
            tckt.REVOKE_FRIEND_FOR_TYPEHASH(),
            keccak256("RevokeFriendFor(address friend)")
        );
        assertEq(
            tckt.CREATE_FOR_TYPEHASH(),
            keccak256("CreateFor(uint256 handle)")
        );
        assertEq(
            tckt.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("TCKT")),
                    keccak256(bytes("1")),
                    43114,
                    0xcCc0FD2f0D06873683aC90e8d89B79d62236BcCc
                )
            )
        );
    }

    function testViewFunctions() external {
        tckt.create(0x1337ACC);
        assertEq(tckt.handleOf(address(this)), 0x1337ACC);
        assertEq(tckt.balanceOf(address(this)), 1);
        assertTrue(tckt.supportsInterface(type(IERC165).interfaceId));
    }

    event RevokerAssignment(
        address indexed owner,
        address indexed revoker,
        uint256 weight
    );

    function testCreateWithRevokers() external {
        vm.expectEmit(true, true, false, true, address(tckt));
        emit RevokerAssignment(address(this), vm.addr(10), 3);
        emit RevokerAssignment(address(this), vm.addr(11), 4);
        emit RevokerAssignment(address(this), vm.addr(12), 5);
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
        assertEq(tckt.revokerWeight(address(this), vm.addr(10)), 3);
        assertEq(tckt.revokerWeight(address(this), vm.addr(11)), 4);
        assertEq(tckt.revokerWeight(address(this), vm.addr(12)), 5);

        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                0,
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                0,
                0,
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(11)),
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(10)),
                (uint256(5) << 160) | uint160(vm.addr(11)),
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(10)),
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(address(this)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(address(this)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
        vm.expectRevert();
        tckt.createWithRevokers(
            0x1337cCc0,
            [
                (uint256(7) << 192) |
                    (uint256(3) << 160) |
                    uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(address(this)),
                0,
                0
            ]
        );
    }

    function testLastRevokeTime() external {
        vm.startPrank(vm.addr(11));
        tckt.create(0xAAAA);
        vm.warp(1000);
        tckt.revoke();

        assertEq(tckt.lastRevokeTimestamp(vm.addr(11)), 1000);

        vm.warp(2000);
        tckt.revoke();

        assertGe(tckt.lastRevokeTimestamp(vm.addr(11)), 1000);

        tckt.createWithRevokers(
            0xAAAA,
            [
                (uint256(31) << 192) |
                    (uint256(10) << 160) |
                    uint160(vm.addr(1)),
                (uint256(10) << 160) | uint160(vm.addr(2)),
                (uint256(10) << 160) | uint160(vm.addr(3)),
                (uint256(10) << 160) | uint160(vm.addr(4)),
                (uint256(10) << 160) | uint160(vm.addr(5))
            ]
        );
        vm.stopPrank();

        vm.warp(3001);
        assertGe(tckt.lastRevokeTimestamp(vm.addr(11)), 1000);

        vm.prank(vm.addr(1));
        tckt.revokeFriend(vm.addr(11));

        assertGe(tckt.lastRevokeTimestamp(vm.addr(11)), 1000);

        vm.warp(3002);
        vm.prank(vm.addr(2));
        tckt.revokeFriend(vm.addr(11));

        vm.warp(3003);
        vm.prank(vm.addr(3));
        tckt.revokeFriend(vm.addr(11));

        vm.warp(3004);
        vm.prank(vm.addr(4));
        tckt.revokeFriend(vm.addr(11));

        assertEq(tckt.lastRevokeTimestamp(vm.addr(11)), 3004);
    }
}
