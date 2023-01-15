// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {MockERC20Permit} from "interfaces/testing/MockTokens.sol";
import {OYLAMA, TCKO_DEPLOYER, TCKT_SIGNERS_DEPLOYER} from "interfaces/Addresses.sol";
import {TCKTSigners} from "contracts/TCKTSigners.sol";

contract TCKTSignersTest is Test {
    MockERC20Permit private tcko;
    TCKTSigners private tcktSigners;

    function setUp() external {
        vm.prank(TCKO_DEPLOYER);
        tcko = new MockERC20Permit("TCKO", "TCKO", 6);

        vm.prank(TCKT_SIGNERS_DEPLOYER);
        tcktSigners = new TCKTSigners();

        vm.prank(OYLAMA);
        tcktSigners.setStakingDeposit(1e12);
    }

    function prepareSigners() public {
        for (uint256 i = 1; i <= 20; ++i) {
            vm.startPrank(vm.addr(i));
            tcko.mint(1e12);
            tcko.approve(address(tcktSigners), 1e12);
            vm.stopPrank();
        }
    }

    function testTCKOstInterface() external {
        assertEq(tcktSigners.name(), "Staked TCKO");
        assertEq(tcktSigners.symbol(), "TCKO-st");
        assertEq(tcktSigners.decimals(), tcko.decimals());
    }

    function testAuthorization() external {
        vm.expectRevert();
        tcktSigners.setStakingDeposit(2e12);
        vm.prank(OYLAMA);
        tcktSigners.setStakingDeposit(2e12);
        assertEq(tcktSigners.stakingDeposit(), 2e12);

        vm.expectRevert();
        tcktSigners.setSignerCountNeeded(5);
        vm.prank(OYLAMA);
        tcktSigners.setSignerCountNeeded(5);
        assertEq(tcktSigners.signerCountNeeded(), 5);

        vm.expectRevert();
        tcktSigners.setSignerStakeNeeded(80_000);
        vm.prank(OYLAMA);
        tcktSigners.setSignerStakeNeeded(80_000);
        assertEq(tcktSigners.signerStakeNeeded(), 80_000);

        vm.expectRevert();
        tcktSigners.approveSignerNode(vm.addr(2));

        vm.startPrank(vm.addr(2));
        tcko.approve(address(tcktSigners), tcktSigners.stakingDeposit());
        tcko.mint(tcktSigners.stakingDeposit());
        vm.stopPrank();

        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));
    }

    function testStateTransition() external {
        vm.startPrank(vm.addr(1));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(2));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(1));
        vm.expectRevert();
        tcktSigners.unstake();
        vm.expectRevert();
        tcktSigners.withdraw();
        vm.stopPrank();

        vm.warp(10001);
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));

        assertEq(
            uint224(tcktSigners.signerInfo(vm.addr(1))),
            (1e12 << 64) | 10001
        );

        vm.warp(10002);
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));

        assertEq(
            uint224(tcktSigners.signerInfo(vm.addr(2))),
            (1e12 << 64) | 10002
        );

        vm.warp(10003);
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(2));

        assertEq(
            uint224(tcktSigners.signerInfo(vm.addr(2))),
            (uint256(10003) << 112) | (1e12 << 64) | 10002
        );

        vm.warp(10004);
        vm.startPrank(vm.addr(1));

        vm.expectRevert();
        tcktSigners.withdraw();

        tcktSigners.unstake();

        vm.expectRevert();
        tcktSigners.unstake();

        vm.warp(10005 + 30 days);
        tcktSigners.withdraw();
        vm.stopPrank();

        assertEq(tcko.balanceOf(vm.addr(1)), 2e12);
    }

    function testSlashWhileUnstaking() external {
        vm.startPrank(vm.addr(1));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(2));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        tcktSigners.approveSignerNode(vm.addr(2));
        vm.stopPrank();

        vm.warp(100);
        vm.prank(vm.addr(1));
        tcktSigners.unstake();
        vm.warp(200);
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(1));

        assertEq(tcktSigners.balanceOf(vm.addr(1)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 2e12);
    }

    function testBalanceOf() external {
        prepareSigners();

        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 1e12);
        }

        for (uint256 t = 5; t > 1; --t) {
            tcktSigners.slashSignerNode(vm.addr(t));
            for (uint256 i = t; i <= 5; ++i)
                assertEq(tcktSigners.balanceOf(vm.addr(i)), 0);

            uint256 balance = 5e12 / (t - 1);
            for (uint256 i = 1; i < t; ++i)
                assertApproxEqAbs(
                    balance,
                    tcktSigners.balanceOf(vm.addr(i)),
                    5
                );
        }
        vm.stopPrank();

        assertEq(tcktSigners.balanceOf(vm.addr(111)), 0);
    }

    function testUnstake() external {
        prepareSigners();
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        vm.prank(vm.addr(5));
        tcktSigners.unstake();
        assertEq(tcko.balanceOf(vm.addr(5)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(5)), 1e12);

        vm.warp(6 + 30 days);
        vm.prank(vm.addr(5));
        tcktSigners.withdraw();
        assertEq(tcko.balanceOf(vm.addr(5)), 1e12);
        assertEq(tcktSigners.balanceOf(vm.addr(5)), 0);
    }

    function testUnstakeSlash() external {
        prepareSigners();
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        vm.prank(vm.addr(5));
        tcktSigners.unstake();
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(4));

        assertEq(tcktSigners.balanceOf(vm.addr(1)), 1333333333333);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 1333333333333);
        assertEq(tcktSigners.balanceOf(vm.addr(3)), 1333333333333);

        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(6));
        assertEq(tcktSigners.balanceOf(vm.addr(6)), 1e12);

        vm.warp(10);
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(3));
        assertEq(tcktSigners.balanceOf(vm.addr(1)), 1777777777777);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 1777777777777);
        assertEq(tcktSigners.balanceOf(vm.addr(5)), 1e12);
        assertEq(tcktSigners.balanceOf(vm.addr(6)), 1444444444444);

        vm.warp(10 + 30 days);
        vm.prank(vm.addr(5));
        tcktSigners.withdraw();
        assertEq(tcktSigners.balanceOf(vm.addr(1)), 1777777777777);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 1777777777777);
        assertEq(tcktSigners.balanceOf(vm.addr(5)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(6)), 1444444444444);
    }

    function testJointDeposit() external {
        prepareSigners();
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        vm.warp(6);
        vm.startPrank(vm.addr(101));
        tcko.mint(10e12);
        tcko.approve(address(tcktSigners), 10e12);
        tcktSigners.jointDeposit(10e12);
        vm.stopPrank();

        for (uint256 t = 1; t <= 5; ++t)
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 3e12);
    }

    function testJointDepositBalanceOf() external {
        prepareSigners();
        vm.startPrank(vm.addr(100));
        tcko.mint(100e12);
        tcko.approve(address(tcktSigners), 100e12);
        vm.stopPrank();

        for (uint256 t = 1; t < 20; t += 2) {
            vm.warp(t);
            vm.prank(OYLAMA);
            tcktSigners.approveSignerNode(vm.addr(t));
            vm.warp(t + 1);
            vm.prank(vm.addr(100));
            tcktSigners.jointDeposit(10e12);
        }

        vm.warp(21);
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(20));
        assertEq(tcktSigners.balanceOf(vm.addr(20)), 1e12);

        uint256 expected1 = uint256(73810e12 + 2520e12) / 2520;
        assertEq(tcktSigners.balanceOf(vm.addr(19)), 2e12);
        assertEq(tcktSigners.balanceOf(vm.addr(1)), expected1);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(3)), expected1 - 10e12);
        assertEq(tcktSigners.balanceOf(vm.addr(4)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(5)), expected1 - 15e12);
        assertEq(tcktSigners.balanceOf(vm.addr(6)), 0);
        assertApproxEqAbs(
            tcktSigners.balanceOf(vm.addr(7)),
            expected1 - 15e12 - uint256(10e12) / 3,
            5
        );
    }

    function testDepositBalanceOf() external {
        prepareSigners();
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        assertEq(
            tcktSigners.depositBalanceOf(vm.addr(1)),
            tcktSigners.stakingDeposit()
        );

        vm.warp(100);
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));
        vm.warp(101);
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(2));
        assertEq(tcktSigners.depositBalanceOf(vm.addr(1)), 1e12);
        assertEq(tcktSigners.depositBalanceOf(vm.addr(2)), 1e12);
        assertEq(tcktSigners.balanceOf(vm.addr(1)), 2e12);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 0);
    }

    function testStakedToken() external {
        prepareSigners();
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        assertEq(
            tcko.balanceOf(address(tcktSigners)),
            tcktSigners.stakingDeposit()
        );
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));
        assertEq(
            tcko.balanceOf(address(tcktSigners)),
            2 * tcktSigners.stakingDeposit()
        );
        assertFalse(tcktSigners.approve(address(this), 0));
        assertEq(tcktSigners.allowance(address(this), address(this)), 0);
        assertFalse(tcktSigners.transfer(address(this), 1));

        assertEq(
            tcktSigners.totalSupply(),
            tcko.balanceOf(address(tcktSigners))
        );
        assertEq(tcktSigners.decimals(), tcko.decimals());
    }

    function testStateTransitionMultiple() external {
        for (uint256 t = 1; t <= 10; ++t) {
            vm.startPrank(vm.addr(t));
            tcko.mint(1e12);
            tcko.approve(address(tcktSigners), 1e12);
            vm.expectRevert();
            tcktSigners.unstake();
            vm.expectRevert();
            tcktSigners.withdraw();
            vm.stopPrank();
        }

        vm.warp(10001);
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(
                uint224(tcktSigners.signerInfo(vm.addr(t))),
                (1e12 << 64) | 10001
            );
        }
        vm.stopPrank();

        vm.warp(10002);
        vm.startPrank(OYLAMA);
        for (uint256 t = 6; t <= 10; t++) {
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(
                uint224(tcktSigners.signerInfo(vm.addr(t))),
                (1e12 << 64) | 10002
            );
        }
        vm.stopPrank();

        vm.warp(10003);
        vm.startPrank(OYLAMA);
        for (uint256 t = 6; t <= 10; t++) {
            tcktSigners.slashSignerNode(vm.addr(t));
            assertEq(
                uint224(tcktSigners.signerInfo(vm.addr(t))),
                (uint256(10003) << 112) | (1e12 << 64) | 10002
            );
        }
        vm.stopPrank();

        vm.warp(10004);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.startPrank(vm.addr(t));
            vm.expectRevert();
            tcktSigners.withdraw();

            tcktSigners.unstake();

            vm.expectRevert();
            tcktSigners.unstake();
            vm.stopPrank();
        }

        vm.warp(10005 + 30 days);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.startPrank(vm.addr(t));
            tcktSigners.withdraw();
            vm.stopPrank();
        }

        assertApproxEqAbs(tcko.balanceOf(vm.addr(1)), 2e12, 5);
    }

    function testUnstakeMultiple() external {
        prepareSigners();
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            vm.warp(t);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 1e12);
        }
        vm.stopPrank();

        for (uint256 t = 1; t <= 5; ++t) {
            vm.prank(vm.addr(t));
            tcktSigners.unstake();
            assertEq(tcko.balanceOf(vm.addr(t)), 0);
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 1e12);
        }

        vm.warp(6 + 30 days);

        for (uint256 t = 1; t <= 5; ++t) {
            vm.prank(vm.addr(t));
            tcktSigners.withdraw();
            assertEq(tcko.balanceOf(vm.addr(t)), 1e12);
            assertEq(tcktSigners.balanceOf(vm.addr(t)), 0);
        }
    }

    function testApproveSignerNode() external {
        prepareSigners();

        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 10; ++t) {
            vm.warp(t);
            assertEq(tcktSigners.signerInfo(vm.addr(t)), 0);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(
                tcktSigners.depositBalanceOf(vm.addr(t)),
                tcktSigners.stakingDeposit()
            );
            assertEq(
                tcko.balanceOf(address(tcktSigners)),
                t * tcktSigners.stakingDeposit()
            );
            assertEq(
                uint112(tcktSigners.signerInfo(vm.addr(t))),
                (tcktSigners.stakingDeposit() << 64) | block.timestamp
            );
        }
        vm.stopPrank();
    }

    function testSlashSignerNode() external {
        prepareSigners();

        vm.warp(100);
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 5; ++t) {
            assertEq(tcktSigners.signerInfo(vm.addr(t)), 0);
            tcktSigners.approveSignerNode(vm.addr(t));
            assertEq(
                tcktSigners.depositBalanceOf(vm.addr(t)),
                tcktSigners.stakingDeposit()
            );
            assertEq(
                tcko.balanceOf(address(tcktSigners)),
                t * tcktSigners.stakingDeposit()
            );
        }
        vm.stopPrank();

        vm.warp(101);
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(1));

        vm.warp(102);
        vm.startPrank(vm.addr(2));
        tcktSigners.unstake();
        vm.expectRevert();
        tcktSigners.withdraw();
        vm.stopPrank();

        vm.warp(103);
        vm.startPrank(vm.addr(3));
        tcktSigners.unstake();
        vm.expectRevert();
        tcktSigners.withdraw();
        vm.stopPrank();

        vm.warp(102 + 31 days);
        vm.prank(vm.addr(2));
        tcktSigners.withdraw();

        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(4));

        vm.warp(103 + 31 days);
        vm.prank(vm.addr(3));
        tcktSigners.withdraw();

        assertEq(tcktSigners.balanceOf(vm.addr(1)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(2)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(3)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(4)), 0);
        assertEq(tcktSigners.balanceOf(vm.addr(5)), 25e11);
        assertEq(tcko.balanceOf(vm.addr(1)), 0);
        assertEq(tcko.balanceOf(vm.addr(2)), 125e10);
        assertEq(tcko.balanceOf(vm.addr(3)), 125e10);
        assertEq(tcko.balanceOf(vm.addr(4)), 0);
        assertEq(tcko.balanceOf(vm.addr(5)), 0);
    }

    function testTotalBalancePreserved() external {
        prepareSigners();
        vm.warp(100);
        vm.startPrank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        tcktSigners.approveSignerNode(vm.addr(2));
        tcktSigners.setStakingDeposit(1e12 / 2);
        tcktSigners.approveSignerNode(vm.addr(3));

        vm.warp(101);
        tcktSigners.slashSignerNode(vm.addr(2));
        vm.stopPrank();

        assertEq(tcktSigners.balanceOf(vm.addr(2)), 0);
        assertApproxEqAbs(
            tcktSigners.balanceOf(vm.addr(1)) +
                tcktSigners.balanceOf(vm.addr(3)),
            25e11,
            5
        );
    }

    function testColorIsPreserved() external {
        prepareSigners();
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t <= 11; ++t) {
            vm.warp(t);
            tcktSigners.approveSignerNode(vm.addr(t));
        }
        vm.stopPrank();

        uint256 color = tcktSigners.signerInfo(vm.addr(1)) >> 224;
        vm.prank(vm.addr(1));
        tcktSigners.unstake();

        assertEq(tcktSigners.signerInfo(vm.addr(1)) >> 224, color);

        vm.warp(12 + 30 days);
        vm.prank(vm.addr(1));
        tcktSigners.withdraw();

        assertEq(tcktSigners.signerInfo(vm.addr(1)) >> 224, color);

        uint256 color2 = tcktSigners.signerInfo(vm.addr(2)) >> 224;
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(2));

        assertEq(tcktSigners.signerInfo(vm.addr(2)) >> 224, color2);
    }

    function testSlashPermutationInvariance() external {
        prepareSigners();
        vm.startPrank(OYLAMA);
        vm.warp(0);
        for (uint256 s = 1; s <= 11; ++s)
            tcktSigners.approveSignerNode(vm.addr(s));
        // Slash signers 2, ..., 11 in some arbitrary order.
        for (uint256 t = 1; t < 11; ++t) {
            vm.warp(t);
            tcktSigners.slashSignerNode(vm.addr(((t * 8) % 11) + 1));
        }
        vm.stopPrank();

        assertApproxEqAbs(tcktSigners.balanceOf(vm.addr(1)), 11e12, 5);
    }

    function testScenarioA() external {
        vm.warp(0);
        for (uint256 s = 1; s <= 19; ++s) {
            vm.startPrank(vm.addr(s));
            tcko.mint(s * 1e12);
            tcko.approve(address(tcktSigners), s * 1e12);
            vm.stopPrank();
            vm.startPrank(OYLAMA);
            tcktSigners.setStakingDeposit(uint48(s * 1e12));
            tcktSigners.approveSignerNode(vm.addr(s));
            vm.stopPrank();
        }

        // Slash nodes 2 through 19 in some arbitrary order.
        vm.startPrank(OYLAMA);
        for (uint256 t = 1; t < 19; ++t) {
            vm.warp(t);
            tcktSigners.slashSignerNode(vm.addr(((t * 17) % 19) + 1));
        }
        vm.stopPrank();

        // (19 * 20) / 2 = 190
        assertApproxEqAbs(tcktSigners.balanceOf(vm.addr(1)), 190e12, 20);

        vm.prank(OYLAMA);
        tcktSigners.setStakingDeposit(20e12);
        for (uint256 t = 20; t < 24; ++t) {
            vm.warp(t);
            vm.startPrank(vm.addr(t));
            tcko.mint(20e12);
            tcko.approve(address(tcktSigners), 20e12);
            vm.stopPrank();
            vm.prank(OYLAMA);
            tcktSigners.approveSignerNode(vm.addr(t));
        }

        vm.warp(24);

        vm.prank(vm.addr(21));
        tcktSigners.unstake();

        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(23));

        assertApproxEqAbs(
            tcktSigners.balanceOf(vm.addr(22)),
            20e12 + uint256(400e12) / 41,
            20
        );

        vm.prank(vm.addr(22));
        tcktSigners.unstake();

        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(20));

        vm.warp(25 + 30 days);

        vm.prank(vm.addr(22));
        tcktSigners.withdraw();

        vm.prank(vm.addr(21));
        tcktSigners.withdraw();

        assertApproxEqAbs(tcko.balanceOf(vm.addr(21)), 20e12, 25);
        assertApproxEqAbs(
            tcko.balanceOf(vm.addr(22)),
            20e12 + uint256(400e12) / 41,
            20
        );
        assertApproxEqAbs(
            tcktSigners.balanceOf(vm.addr(1)),
            210e12 + (21 * uint256(20e12)) / 41,
            20
        );
    }
}
