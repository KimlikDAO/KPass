// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {KPassSigners} from "../KPassSigners.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Permit as MockERC20Permit} from "interfaces/erc/mock/ERC20Permit.sol";
import {SignerInfo} from "interfaces/kimlikdao/IDIDSigners.sol";
import {KDAO_DEPLOYER, KPASS_SIGNERS_DEPLOYER, VOTING} from "interfaces/kimlikdao/addresses.sol";
import {KDAO} from "interfaces/kimlikdao/mock/KDAO.sol";

contract KPassSignersTest is Test {
    MockERC20Permit private kdao;
    KPassSigners private kpassSigners;

    function setUp() external {
        vm.prank(KDAO_DEPLOYER);
        kdao = new KDAO();

        vm.prank(KPASS_SIGNERS_DEPLOYER);
        kpassSigners = new KPassSigners();

        vm.prank(VOTING);
        kpassSigners.setStakingDeposit(1e12);
    }

    function prepareSigners() public {
        for (uint256 i = 1; i <= 20; ++i) {
            vm.startPrank(vm.addr(i));
            kdao.mint(1e12);
            kdao.approve(address(kpassSigners), 1e12);
            vm.stopPrank();
        }
    }

    function testKDAOstInterface() external view {
        assertEq(kpassSigners.name(), "Staked KDAO");
        assertEq(kpassSigners.symbol(), "KDAO-st");
        assertEq(kpassSigners.decimals(), kdao.decimals());
    }

    function testAuthorization() external {
        vm.expectRevert();
        kpassSigners.setStakingDeposit(2e12);
        vm.prank(VOTING);
        kpassSigners.setStakingDeposit(2e12);
        assertEq(kpassSigners.stakingDeposit(), 2e12);

        vm.expectRevert();
        kpassSigners.setSignerCountNeeded(5);
        vm.prank(VOTING);
        kpassSigners.setSignerCountNeeded(5);
        assertEq(kpassSigners.signerCountNeeded(), 5);

        vm.expectRevert();
        kpassSigners.setSignerStakeNeeded(80_000);
        vm.prank(VOTING);
        kpassSigners.setSignerStakeNeeded(80_000);
        assertEq(kpassSigners.signerStakeNeeded(), 80_000);

        vm.expectRevert();
        kpassSigners.approveSignerNode(vm.addr(2));

        vm.startPrank(vm.addr(2));
        kdao.approve(address(kpassSigners), kpassSigners.stakingDeposit());
        kdao.mint(kpassSigners.stakingDeposit());
        vm.stopPrank();

        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(2));
    }

    function testStateTransition() external {
        vm.startPrank(vm.addr(1));
        kdao.mint(1e12);
        kdao.approve(address(kpassSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(2));
        kdao.mint(1e12);
        kdao.approve(address(kpassSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(1));
        vm.expectRevert();
        kpassSigners.unstake();
        vm.expectRevert();
        kpassSigners.withdraw();
        vm.stopPrank();

        vm.warp(10001);
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));

        assertEq(
            uint224(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(1)))), (1e12 << 64) | 10001
        );

        vm.warp(10002);
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(2));

        assertEq(
            uint224(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(2)))), (1e12 << 64) | 10002
        );

        vm.warp(10003);
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(2));

        assertEq(
            uint224(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(2)))),
            (uint256(10003) << 112) | (1e12 << 64) | 10002
        );

        vm.warp(10004);
        vm.startPrank(vm.addr(1));

        vm.expectRevert();
        kpassSigners.withdraw();

        kpassSigners.unstake();

        vm.expectRevert();
        kpassSigners.unstake();

        vm.warp(10005 + 30 days);
        kpassSigners.withdraw();
        vm.stopPrank();

        assertEq(kdao.balanceOf(vm.addr(1)), 2e12);
    }

    function testSlashWhileUnstaking() external {
        vm.startPrank(vm.addr(1));
        kdao.mint(1e12);
        kdao.approve(address(kpassSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(2));
        kdao.mint(1e12);
        kdao.approve(address(kpassSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));
        kpassSigners.approveSignerNode(vm.addr(2));
        vm.stopPrank();

        vm.warp(100);
        vm.prank(vm.addr(1));
        kpassSigners.unstake();
        vm.warp(200);
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(1));

        assertEq(kpassSigners.balanceOf(vm.addr(1)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 2e12);
    }

    function testBalanceOf() external {
        prepareSigners();

        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 1e12);
        }

        for (uint256 t = 5; t > 1; --t) {
            kpassSigners.slashSignerNode(vm.addr(t));
            for (uint256 i = t; i <= 5; ++i) {
                assertEq(kpassSigners.balanceOf(vm.addr(i)), 0);
            }

            uint256 balance = 5e12 / (t - 1);
            for (uint256 i = 1; i < t; ++i) {
                assertApproxEqAbs(balance, kpassSigners.balanceOf(vm.addr(i)), 5);
            }
        }
        vm.stopPrank();

        assertEq(kpassSigners.balanceOf(vm.addr(111)), 0);
    }

    function testUnstake() external {
        prepareSigners();
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        vm.prank(vm.addr(5));
        kpassSigners.unstake();
        assertEq(kdao.balanceOf(vm.addr(5)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(5)), 1e12);

        vm.warp(6 + 30 days);
        vm.prank(vm.addr(5));
        kpassSigners.withdraw();
        assertEq(kdao.balanceOf(vm.addr(5)), 1e12);
        assertEq(kpassSigners.balanceOf(vm.addr(5)), 0);
    }

    function testUnstakeSlash() external {
        prepareSigners();
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        vm.prank(vm.addr(5));
        kpassSigners.unstake();
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(4));

        assertEq(kpassSigners.balanceOf(vm.addr(1)), 1333333333333);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 1333333333333);
        assertEq(kpassSigners.balanceOf(vm.addr(3)), 1333333333333);

        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(6));
        assertEq(kpassSigners.balanceOf(vm.addr(6)), 1e12);

        vm.warp(10);
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(3));
        assertEq(kpassSigners.balanceOf(vm.addr(1)), 1777777777777);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 1777777777777);
        assertEq(kpassSigners.balanceOf(vm.addr(5)), 1e12);
        assertEq(kpassSigners.balanceOf(vm.addr(6)), 1444444444444);

        vm.warp(10 + 30 days);
        vm.prank(vm.addr(5));
        kpassSigners.withdraw();
        assertEq(kpassSigners.balanceOf(vm.addr(1)), 1777777777777);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 1777777777777);
        assertEq(kpassSigners.balanceOf(vm.addr(5)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(6)), 1444444444444);
    }

    function testJointDeposit() external {
        prepareSigners();
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        vm.warp(6);
        vm.startPrank(vm.addr(101));
        kdao.mint(10e12);
        kdao.approve(address(kpassSigners), 10e12);
        kpassSigners.jointDeposit(10e12);
        vm.stopPrank();

        for (uint256 t = 1; t <= 5; ++t) {
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 3e12);
        }
    }

    function testJointDepositBalanceOf() external {
        prepareSigners();
        vm.startPrank(vm.addr(100));
        kdao.mint(100e12);
        kdao.approve(address(kpassSigners), 100e12);
        vm.stopPrank();

        for (uint256 t = 1; t < 20; t += 2) {
            vm.warp(t);
            vm.prank(VOTING);
            kpassSigners.approveSignerNode(vm.addr(t));
            vm.warp(t + 1);
            vm.prank(vm.addr(100));
            kpassSigners.jointDeposit(10e12);
        }

        vm.warp(21);
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(20));
        assertEq(kpassSigners.balanceOf(vm.addr(20)), 1e12);

        uint256 expected1 = uint256(73810e12 + 2520e12) / 2520;
        assertEq(kpassSigners.balanceOf(vm.addr(19)), 2e12);
        assertEq(kpassSigners.balanceOf(vm.addr(1)), expected1);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(3)), expected1 - 10e12);
        assertEq(kpassSigners.balanceOf(vm.addr(4)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(5)), expected1 - 15e12);
        assertEq(kpassSigners.balanceOf(vm.addr(6)), 0);
        assertApproxEqAbs(
            kpassSigners.balanceOf(vm.addr(7)), expected1 - 15e12 - uint256(10e12) / 3, 5
        );
    }

    function testDepositBalanceOf() external {
        prepareSigners();
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));
        assertEq(kpassSigners.depositBalanceOf(vm.addr(1)), kpassSigners.stakingDeposit());

        vm.warp(100);
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(2));
        vm.warp(101);
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(2));
        assertEq(kpassSigners.depositBalanceOf(vm.addr(1)), 1e12);
        assertEq(kpassSigners.depositBalanceOf(vm.addr(2)), 1e12);
        assertEq(kpassSigners.balanceOf(vm.addr(1)), 2e12);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 0);
    }

    function testStakedToken() external {
        prepareSigners();
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));
        assertEq(kdao.balanceOf(address(kpassSigners)), kpassSigners.stakingDeposit());
        vm.prank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(2));
        assertEq(kdao.balanceOf(address(kpassSigners)), 2 * kpassSigners.stakingDeposit());
        assertFalse(kpassSigners.approve(address(this), 0));
        assertEq(kpassSigners.allowance(address(this), address(this)), 0);
        assertFalse(kpassSigners.transfer(address(this), 1));

        assertEq(kpassSigners.totalSupply(), kdao.balanceOf(address(kpassSigners)));
        assertEq(kpassSigners.decimals(), kdao.decimals());
    }

    function testStateTransitionMultiple() external {
        for (uint256 t = 1; t <= 10; ++t) {
            vm.startPrank(vm.addr(t));
            kdao.mint(1e12);
            kdao.approve(address(kpassSigners), 1e12);
            vm.expectRevert();
            kpassSigners.unstake();
            vm.expectRevert();
            kpassSigners.withdraw();
            vm.stopPrank();
        }

        vm.warp(10001);
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(
                uint224(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(t)))),
                (1e12 << 64) | 10001
            );
        }
        vm.stopPrank();

        vm.warp(10002);
        vm.startPrank(VOTING);
        for (uint256 t = 6; t <= 10; t++) {
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(
                uint224(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(t)))),
                (1e12 << 64) | 10002
            );
        }
        vm.stopPrank();

        vm.warp(10003);
        vm.startPrank(VOTING);
        for (uint256 t = 6; t <= 10; t++) {
            kpassSigners.slashSignerNode(vm.addr(t));
            assertEq(
                uint224(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(t)))),
                (uint256(10003) << 112) | (1e12 << 64) | 10002
            );
        }
        vm.stopPrank();

        vm.warp(10004);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.startPrank(vm.addr(t));
            vm.expectRevert();
            kpassSigners.withdraw();

            kpassSigners.unstake();

            vm.expectRevert();
            kpassSigners.unstake();
            vm.stopPrank();
        }

        vm.warp(10005 + 30 days);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.startPrank(vm.addr(t));
            kpassSigners.withdraw();
            vm.stopPrank();
        }

        assertApproxEqAbs(kdao.balanceOf(vm.addr(1)), 2e12, 5);
    }

    function testUnstakeMultiple() external {
        prepareSigners();
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        for (uint256 t = 1; t <= 5; ++t) {
            vm.prank(vm.addr(t));
            kpassSigners.unstake();
            assertEq(kdao.balanceOf(vm.addr(t)), 0);
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 1e12);
        }

        vm.warp(6 + 30 days);

        for (uint256 t = 1; t <= 5; ++t) {
            vm.prank(vm.addr(t));
            kpassSigners.withdraw();
            assertEq(kdao.balanceOf(vm.addr(t)), 1e12);
            assertEq(kpassSigners.balanceOf(vm.addr(t)), 0);
        }
    }

    function testApproveSignerNode() external {
        prepareSigners();

        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 10; ++t) {
            vm.warp(t);
            assertEq(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(t))), 0);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.depositBalanceOf(vm.addr(t)), kpassSigners.stakingDeposit());
            assertEq(kdao.balanceOf(address(kpassSigners)), t * kpassSigners.stakingDeposit());
            assertEq(
                uint112(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(t)))),
                (kpassSigners.stakingDeposit() << 64) | block.timestamp
            );
        }
        vm.stopPrank();
    }

    function testSlashSignerNode() external {
        prepareSigners();

        vm.warp(100);
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 5; ++t) {
            assertEq(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(t))), 0);
            kpassSigners.approveSignerNode(vm.addr(t));
            assertEq(kpassSigners.depositBalanceOf(vm.addr(t)), kpassSigners.stakingDeposit());
            assertEq(kdao.balanceOf(address(kpassSigners)), t * kpassSigners.stakingDeposit());
        }
        vm.stopPrank();

        vm.warp(101);
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(1));

        vm.warp(102);
        vm.startPrank(vm.addr(2));
        kpassSigners.unstake();
        vm.expectRevert();
        kpassSigners.withdraw();
        vm.stopPrank();

        vm.warp(103);
        vm.startPrank(vm.addr(3));
        kpassSigners.unstake();
        vm.expectRevert();
        kpassSigners.withdraw();
        vm.stopPrank();

        vm.warp(102 + 31 days);
        vm.prank(vm.addr(2));
        kpassSigners.withdraw();

        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(4));

        vm.warp(103 + 31 days);
        vm.prank(vm.addr(3));
        kpassSigners.withdraw();

        assertEq(kpassSigners.balanceOf(vm.addr(1)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(2)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(3)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(4)), 0);
        assertEq(kpassSigners.balanceOf(vm.addr(5)), 25e11);
        assertEq(kdao.balanceOf(vm.addr(1)), 0);
        assertEq(kdao.balanceOf(vm.addr(2)), 125e10);
        assertEq(kdao.balanceOf(vm.addr(3)), 125e10);
        assertEq(kdao.balanceOf(vm.addr(4)), 0);
        assertEq(kdao.balanceOf(vm.addr(5)), 0);
    }

    function testTotalBalancePreserved() external {
        prepareSigners();
        vm.warp(100);
        vm.startPrank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));
        kpassSigners.approveSignerNode(vm.addr(2));
        kpassSigners.setStakingDeposit(1e12 / 2);
        kpassSigners.approveSignerNode(vm.addr(3));

        vm.warp(101);
        kpassSigners.slashSignerNode(vm.addr(2));
        vm.stopPrank();

        assertEq(kpassSigners.balanceOf(vm.addr(2)), 0);
        assertApproxEqAbs(
            kpassSigners.balanceOf(vm.addr(1)) + kpassSigners.balanceOf(vm.addr(3)), 25e11, 5
        );
    }

    function testColorIsPreserved() external {
        prepareSigners();
        vm.startPrank(VOTING);
        for (uint256 t = 1; t <= 11; ++t) {
            vm.warp(t);
            kpassSigners.approveSignerNode(vm.addr(t));
        }
        vm.stopPrank();

        uint256 color = SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(1))) >> 224;
        vm.prank(vm.addr(1));
        kpassSigners.unstake();

        assertEq(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(1))) >> 224, color);

        vm.warp(12 + 30 days);
        vm.prank(vm.addr(1));
        kpassSigners.withdraw();

        assertEq(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(1))) >> 224, color);

        uint256 color2 = SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(2))) >> 224;
        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(2));

        assertEq(SignerInfo.unwrap(kpassSigners.signerInfo(vm.addr(2))) >> 224, color2);
    }

    function testSlashPermutationInvariance() external {
        prepareSigners();
        vm.startPrank(VOTING);
        vm.warp(0);
        for (uint256 s = 1; s <= 11; ++s) {
            kpassSigners.approveSignerNode(vm.addr(s));
        }
        // Slash signers 2, ..., 11 in some arbitrary order.
        for (uint256 t = 1; t < 11; ++t) {
            vm.warp(t);
            kpassSigners.slashSignerNode(vm.addr(((t * 8) % 11) + 1));
        }
        vm.stopPrank();

        assertApproxEqAbs(kpassSigners.balanceOf(vm.addr(1)), 11e12, 5);
    }

    function testScenarioA() external {
        vm.warp(0);
        for (uint256 s = 1; s <= 19; ++s) {
            vm.startPrank(vm.addr(s));
            kdao.mint(s * 1e12);
            kdao.approve(address(kpassSigners), s * 1e12);
            vm.stopPrank();
            vm.startPrank(VOTING);
            kpassSigners.setStakingDeposit(uint48(s * 1e12));
            kpassSigners.approveSignerNode(vm.addr(s));
            vm.stopPrank();
        }

        // Slash nodes 2 through 19 in some arbitrary order.
        vm.startPrank(VOTING);
        for (uint256 t = 1; t < 19; ++t) {
            vm.warp(t);
            kpassSigners.slashSignerNode(vm.addr(((t * 17) % 19) + 1));
        }
        vm.stopPrank();

        // (19 * 20) / 2 = 190
        assertApproxEqAbs(kpassSigners.balanceOf(vm.addr(1)), 190e12, 20);

        vm.prank(VOTING);
        kpassSigners.setStakingDeposit(20e12);
        for (uint256 t = 20; t < 24; ++t) {
            vm.warp(t);
            vm.startPrank(vm.addr(t));
            kdao.mint(20e12);
            kdao.approve(address(kpassSigners), 20e12);
            vm.stopPrank();
            vm.prank(VOTING);
            kpassSigners.approveSignerNode(vm.addr(t));
        }

        vm.warp(24);

        vm.prank(vm.addr(21));
        kpassSigners.unstake();

        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(23));

        assertApproxEqAbs(kpassSigners.balanceOf(vm.addr(22)), 20e12 + uint256(400e12) / 41, 20);

        vm.prank(vm.addr(22));
        kpassSigners.unstake();

        vm.prank(VOTING);
        kpassSigners.slashSignerNode(vm.addr(20));

        vm.warp(25 + 30 days);

        vm.prank(vm.addr(22));
        kpassSigners.withdraw();

        vm.prank(vm.addr(21));
        kpassSigners.withdraw();

        assertApproxEqAbs(kdao.balanceOf(vm.addr(21)), 20e12, 25);
        assertApproxEqAbs(kdao.balanceOf(vm.addr(22)), 20e12 + uint256(400e12) / 41, 20);
        assertApproxEqAbs(
            kpassSigners.balanceOf(vm.addr(1)), 210e12 + (21 * uint256(20e12)) / 41, 20
        );
    }
}
