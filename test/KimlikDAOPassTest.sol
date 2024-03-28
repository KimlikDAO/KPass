// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import "interfaces/AvalancheTokens.sol";
import "interfaces/testing/MockTokens.sol";
import {IERC165} from "interfaces/IERC165.sol";
import {IERC20Permit} from "interfaces/IERC20Permit.sol";
import {KimlikDAOPass, Signature} from "contracts/KimlikDAOPass.sol";

contract KimlikDAOPassTest is Test {
    KimlikDAOPass private kpass;

    function setUp() public {
        vm.prank(KPASS_DEPLOYER);
        kpass = new KimlikDAOPass();
        assertEq(address(kpass), KPASS_ADDR);
    }

    function testTokenURI() public view {
        assertEq(
            kpass.tokenURI(0x3d5bad4604650569f28733f7ad6ec22835e775a0eb20bfd809d78ed2ae8abe47),
            "https://ipfs.kimlikdao.org/ipfs/QmSUAf9gusxTbZZn5nC7d44kHjfrDeu2gfSY31MRVET28n"
        );
        assertEq(
            kpass.tokenURI(0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523),
            "https://ipfs.kimlikdao.org/ipfs/QmcX2ScFVAVnEHrMk3xuf7HXfiGHzmMqdpAYb37zA5mbFp"
        );
        assertEq(
            kpass.tokenURI(uint256(keccak256("CID test 1"))),
            "https://ipfs.kimlikdao.org/ipfs/QmVh6DdiLVjUndMVBmdoG1hXKuWFiUdbUFqqPBkhtNxJhA"
        );
        assertEq(
            kpass.tokenURI(uint256(keccak256("CID test 2"))),
            "https://ipfs.kimlikdao.org/ipfs/QmcbtE4RC2KFStbyjCnjACgNSxZJSKww2XGFRAMFVG4sNu"
        );
        assertEq(
            kpass.tokenURI(uint256(keccak256("CID test 3"))),
            "https://ipfs.kimlikdao.org/ipfs/QmQY9mWApretyH5dVMuqPThn299xNRp1knzuF9yMuF9kmM"
        );
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

    function testAuthenticationPriceFeeder() public {
        vm.expectRevert();
        kpass.updatePrice((15 << 160) | uint160(vm.addr(1)));

        vm.prank(VOTING);
        kpass.updatePrice((15 << 160) | uint160(vm.addr(1)));
        assertEq(uint128(kpass.priceIn(vm.addr(1))), 15);

        uint256[5] memory prices = [(uint256(17) << 160) | 1337, 0, 0, 0, 0];

        vm.expectRevert();
        kpass.updatePricesBulk((1 << 128) + 1, prices);

        vm.prank(VOTING);
        kpass.updatePricesBulk((1 << 128) + 1, prices);
        assertEq(uint128(kpass.priceIn(address(1337))), 17);
    }

    function testUpdatePrice() public {
        vm.prank(VOTING);

        kpass.updatePrice((131 << 160) | uint160(vm.addr(888)));
        assertEq(uint128(kpass.priceIn(vm.addr(888))), 131);
        assertEq(kpass.priceIn(vm.addr(888)) >> 128, uint256(131 * 3) / 2);
    }

    function testUpdatePricesBulk() public {
        vm.prank(VOTING);
        kpass.updatePricesBulk(
            (uint256(7) << 128) | 5,
            [
                (uint256(5) << 160) | uint160(vm.addr(1)),
                (uint256(6) << 160) | uint160(vm.addr(2)),
                (uint256(7) << 160) | uint160(vm.addr(3)),
                (uint256(8) << 160) | uint160(vm.addr(4)),
                (uint256(9) << 160) | uint160(vm.addr(5))
            ]
        );

        assertEq(uint128(kpass.priceIn(vm.addr(1))), 5);
        assertEq(kpass.priceIn(vm.addr(1)) >> 128, 7);
        assertEq(uint128(kpass.priceIn(vm.addr(2))), 6);
        assertEq(kpass.priceIn(vm.addr(2)) >> 128, 8);
        assertEq(uint128(kpass.priceIn(vm.addr(3))), 7);
        assertEq(kpass.priceIn(vm.addr(3)) >> 128, 9);
        assertEq(uint128(kpass.priceIn(vm.addr(4))), 8);
        assertEq(kpass.priceIn(vm.addr(4)) >> 128, 11);
        assertEq(uint128(kpass.priceIn(vm.addr(5))), 9);
        assertEq(kpass.priceIn(vm.addr(5)) >> 128, 12);
    }

    function testCreate() public {
        vm.prank(VOTING);
        kpass.updatePrice(5e16 << 160);

        vm.expectRevert();
        kpass.create(123123123);

        vm.expectRevert();
        kpass.create{value: 0.074 ether}(123123123);

        vm.prank(VOTING);
        kpass.updatePrice(4e16 << 160);

        kpass.create{value: 0.06 ether}(1231231233);
        kpass.create{value: 0.07 ether}(123123123);

        vm.prank(VOTING);
        kpass.updatePrice(5e16 << 160);

        vm.expectRevert();
        kpass.create{value: 0.074 ether}(123123123);

        kpass.create{value: 0.075 ether}(1231231233);
    }

    function testUpdate() public {
        vm.expectRevert();
        kpass.update(1338);

        kpass.create{value: 0.075 ether}(1337);
        kpass.update(1338);
    }

    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /**
     * Authorizes a payment from `vm.addr(0x1337ACC)` for the spender
     * `KPASS_ADDR`.
     */
    function authorizePayment(IERC20Permit token, uint256 amount, uint256 deadline, uint256 nonce)
        internal
        view
        returns (Signature memory)
    {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, vm.addr(0x1337ACC), KPASS_ADDR, amount, nonce, deadline))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1337ACC, digest);
        return Signature(r, (uint256(v - 27) << 255) | uint256(s));
    }

    function testUSDTPayment() public {
        DeployMockTokens();

        vm.prank(VOTING);
        // Set KPASS price to 2 USDT
        kpass.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        {
            uint256 deadline = block.timestamp + 1200;
            Signature memory sig = authorizePayment(USDT, 3e6, deadline, 0);

            vm.prank(vm.addr(0x1337ACC));
            uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
            kpass.createWithTokenPermit(123123123, deadlineAndToken, sig);
            assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);
        }

        vm.prank(vm.addr(0x1337ACC));
        kpass.revoke();
        {
            uint256 deadline = block.timestamp + 1200;
            Signature memory sig = authorizePayment(USDT, 3e6, deadline, 1);
            uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
            vm.prank(vm.addr(0x1337ACC));
            kpass.createWithTokenPermit(123123123, deadlineAndToken, sig);
            assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);
        }
        vm.prank(vm.addr(0x1337ACC));
        kpass.revoke();
        {
            uint256 deadline = block.timestamp + 1200;
            Signature memory sig = authorizePayment(USDT, 2.999999e6, deadline, 2);
            uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
            vm.prank(vm.addr(0x1337ACC));
            vm.expectRevert();
            kpass.createWithTokenPermit(123123123, deadlineAndToken, sig);
        }
    }

    function testUnsupportedTokenPayment() external {
        DeployMockTokens();
        vm.prank(VOTING);
        // Set KPASS price to 4 USDC
        kpass.updatePrice((4e6 << 160) | uint160(address(USDC)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        uint256 deadline = block.timestamp + 1200;
        Signature memory sig = authorizePayment(USDT, 6e6, deadline, 0);

        vm.prank(vm.addr(0x1337ACC));
        uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
        vm.expectRevert();
        kpass.createWithTokenPermit(123123123, deadlineAndToken, sig);
    }

    function testInvalidSpendSignature() external {
        DeployMockTokens();
        vm.prank(VOTING);
        // Set KPASS price to 4 USDC
        kpass.updatePrice((4e6 << 160) | uint160(address(USDC)));

        vm.prank(USDC_DEPLOYER);
        USDC.transfer(vm.addr(0x1337ACC), 15e6);

        uint256 deadline = block.timestamp + 1200;
        Signature memory sig = authorizePayment(USDC, 6e6, deadline, 0);
        // Break the signature
        sig.yParityAndS -= 1;

        vm.prank(vm.addr(0x1337ACC));
        uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDC));
        vm.expectRevert();
        kpass.createWithTokenPermit(123123123, deadlineAndToken, sig);
    }

    function testApproveAndCreate() external {
        DeployMockTokens();

        vm.prank(VOTING);
        // Set KPASS price to 2 USDT
        kpass.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 10e6);

        vm.startPrank(vm.addr(0x1337ACC));
        USDT.approve(address(kpass), 1e6);
        vm.expectRevert();
        kpass.createWithRevokersWithTokenPayment(
            123123123,
            [
                (uint256(1) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ],
            USDT
        );

        USDT.approve(address(kpass), 2e6);
        kpass.createWithRevokersWithTokenPayment(
            123123123,
            [
                (uint256(1) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ],
            USDT
        );

        assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);
        assertEq(USDT.balanceOf(vm.addr(0x1337ACC)), 8e6);

        USDT.approve(address(kpass), 2e6);
        vm.expectRevert();
        kpass.createWithTokenPayment(123123123, USDT);

        USDT.approve(address(kpass), 3e6);
        kpass.createWithTokenPayment(123123123, USDT);
    }

    // keccak256("CreateFor(uint256 handle)")
    bytes32 CREATE_FOR_TYPEHASH = 0xe0b70ef26ac646b5fe42b7831a9d039e8afa04a2698e03b3321e5ca3516efe70;

    function authorizeCreateFor(uint256 handle) public view returns (Signature memory) {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", kpass.DOMAIN_SEPARATOR(), keccak256(abi.encode(CREATE_FOR_TYPEHASH, handle)))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1337ACC, digest);
        return Signature(r, (uint256(v - 27) << 255) | uint256(s));
    }

    function testCreateFor() public {
        DeployMockTokens();

        vm.deal(VOTING, 100000);
        vm.prank(VOTING);
        // Set KPASS price to 2 USDT
        kpass.updatePrice((2e6 << 160) | uint160(address(USDT)));

        vm.prank(USDT_DEPLOYER);
        USDT.transfer(vm.addr(0x1337ACC), 15e6);

        {
            uint256 deadline = block.timestamp + 1200;
            uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
            vm.startPrank(VOTING);
            kpass.createFor(
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

            assertEq(kpass.balanceOf(vm.addr(0x1337ACC)), 1);
        }

        vm.prank(vm.addr(0x1337ACC));
        kpass.revoke();
        {
            uint256 deadline = block.timestamp + 1200;
            uint256 deadlineAndToken = (deadline << 160) | uint160(address(USDT));
            Signature memory createSig = authorizeCreateFor(123123123);
            Signature memory paymentSig = authorizePayment(USDT, 2.99e6, deadline, 0);
            vm.expectRevert();
            vm.prank(VOTING);
            kpass.createFor(123123123, createSig, deadlineAndToken, paymentSig);
        }
    }

    function testCreateForIntegration() external {
        DeployMockTokens();

        // `VOTING` mints a KPASS on behalf of
        // 0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1.
        // The handle is 0x1337ABCDEF and the KPASS costs 3 USDC.

        vm.prank(VOTING);
        // Set KPASS price to 2 USDC
        kpass.updatePrice((2e6 << 160) | uint160(address(USDC)));

        vm.prank(USDC_DEPLOYER);
        USDC.transfer(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1, 3e6);

        assertEq(kpass.balanceOf(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1), 0);
        assertEq(USDC.balanceOf(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1), 3e6);

        // Give some gas money to VOTING.
        vm.deal(VOTING, 10000000);
        vm.startPrank(VOTING);
        kpass.createFor(
            0x1337ABCDEF,
            Signature(
                0xbbb137f6281d8a9060b315bef0052803d193758e69c5288ec36d79653957bb62,
                0x94f65510a14d3570e8a184e806d6adc501e5214134372c90fd4bb71469808a0e
            ),
            (uint256(123456) << 160) | uint160(address(USDC)),
            Signature(
                0x113b9021944d6ffb785fdee138672300145262883b5c11d1584d09c05e911675,
                0xfc45d4be1afa7c03a669d0c46246d94b4229a91f964365169f6d651ffd6d37f3
            )
        );
        vm.stopPrank();

        assertEq(kpass.balanceOf(0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1), 1);
    }

    function testTypeHashes() external view {
        assertEq(kpass.REVOKE_FRIEND_FOR_TYPEHASH(), keccak256("RevokeFriendFor(address friend)"));
        assertEq(kpass.CREATE_FOR_TYPEHASH(), keccak256("CreateFor(uint256 handle)"));
        assertEq(
            kpass.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("KPASS")),
                    keccak256(bytes("1")),
                    0x144,
                    0xcCc0a9b023177549fcf26c947edb5bfD9B230cCc
                )
            )
        );
    }

    function testViewFunctions() external {
        kpass.create{value: 0.075 ether}(0x70CE4);
        assertEq(kpass.handleOf(address(this)), 0x70CE4);
        assertEq(kpass.balanceOf(address(this)), 1);
        assertTrue(kpass.supportsInterface(type(IERC165).interfaceId));
    }

    event RevokerAssignment(address indexed owner, address indexed revoker, uint256 weight);

    function testCreateWithRevokers() external {
        vm.expectEmit(true, true, false, true, address(kpass));
        emit RevokerAssignment(address(this), vm.addr(10), 3);
        emit RevokerAssignment(address(this), vm.addr(11), 4);
        emit RevokerAssignment(address(this), vm.addr(12), 5);
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
        assertEq(kpass.revokerWeight(address(this), vm.addr(10)), 3);
        assertEq(kpass.revokerWeight(address(this), vm.addr(11)), 4);
        assertEq(kpass.revokerWeight(address(this), vm.addr(12)), 5);

        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                0,
                0,
                0
            ]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0, [(uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)), 0, 0, 0, 0]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(11)),
                0,
                0
            ]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(10)),
                (uint256(5) << 160) | uint160(vm.addr(11)),
                0,
                0
            ]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(10)),
                0,
                0
            ]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(address(this)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(address(this)),
                (uint256(5) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
        vm.expectRevert();
        kpass.createWithRevokers{value: 0.05 ether}(
            0x1337cCc0,
            [
                (uint256(7) << 192) | (uint256(3) << 160) | uint160(vm.addr(10)),
                (uint256(4) << 160) | uint160(vm.addr(11)),
                (uint256(5) << 160) | uint160(address(this)),
                0,
                0
            ]
        );
    }

    function testLastRevokeTimestamp() external {
        vm.deal(vm.addr(11), 1 ether);
        vm.startPrank(vm.addr(11));
        kpass.create{value: 0.075 ether}(0xAAAA);
        vm.warp(1000);
        kpass.revoke();

        assertEq(kpass.lastRevokeTimestamp(vm.addr(11)), 1000);

        vm.warp(2000);
        kpass.revoke();

        assertGe(kpass.lastRevokeTimestamp(vm.addr(11)), 1000);

        kpass.createWithRevokers{value: 0.05 ether}(
            0xAAAA,
            [
                (uint256(31) << 192) | (uint256(10) << 160) | uint160(vm.addr(1)),
                (uint256(10) << 160) | uint160(vm.addr(2)),
                (uint256(10) << 160) | uint160(vm.addr(3)),
                (uint256(10) << 160) | uint160(vm.addr(4)),
                (uint256(10) << 160) | uint160(vm.addr(5))
            ]
        );
        vm.stopPrank();

        vm.warp(3001);
        assertGe(kpass.lastRevokeTimestamp(vm.addr(11)), 1000);

        vm.prank(vm.addr(1));
        kpass.revokeFriend(vm.addr(11));

        assertGe(kpass.lastRevokeTimestamp(vm.addr(11)), 1000);

        vm.warp(3002);
        vm.prank(vm.addr(2));
        kpass.revokeFriend(vm.addr(11));

        vm.warp(3003);
        vm.prank(vm.addr(3));
        kpass.revokeFriend(vm.addr(11));

        vm.warp(3004);
        vm.prank(vm.addr(4));
        kpass.revokeFriend(vm.addr(11));

        assertEq(kpass.lastRevokeTimestamp(vm.addr(11)), 3004);
    }

    function testInitialPrices() external view {
        assertEq(uint128(kpass.priceIn(address(0))), 5e16);
        assertEq(kpass.priceIn(address(0)) >> 128, 75e15);
        assertEq(uint128(kpass.priceIn(address(USDT))), 1e6);
        assertEq(kpass.priceIn(address(USDT)) >> 128, 1.5e6);
        assertEq(uint128(kpass.priceIn(address(USDC))), 1e6);
        assertEq(kpass.priceIn(address(USDC)) >> 128, 1.5e6);
        assertEq(uint128(kpass.priceIn(address(TRYB))), 19e6);
        assertEq(kpass.priceIn(address(TRYB)) >> 128, 28.5e6);
    }
}
