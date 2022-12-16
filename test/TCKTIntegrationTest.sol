// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import {MockERC20Permit} from "interfaces/testing/MockTokens.sol";
import {TCKT} from "contracts/TCKT.sol";
import {TCKTSigners} from "contracts/TCKTSigners.sol";

contract TCKTIntegrationTest is Test {
    MockERC20Permit private tcko;
    TCKT private tckt;
    TCKTSigners private tcktSigners;

    function setUp() public {
        vm.prank(TCKT_DEPLOYER);
        tckt = new TCKT();
        vm.prank(TCKT_SIGNERS_DEPLOYER);
        tcktSigners = new TCKTSigners();
        vm.prank(TCKO_DEPLOYER);
        tcko = new MockERC20Permit("KimlikDAO Tokeni", "TCKO", 6);

        assertEq(address(tckt), TCKT_ADDR);
        assertEq(address(tcktSigners), TCKT_SIGNERS);
        assertEq(address(tcko), TCKO_ADDR);

        for (uint256 i = 1; i <= 10; ++i) {
            vm.startPrank(vm.addr(i));
            tcko.mint(1e12);
            tcko.approve(address(tcktSigners), 1e12);
            vm.stopPrank();
        }
    }

    function signOffExposureReport(
        bytes32 exposureReportID,
        uint64 timestamp,
        uint256 signerKey
    ) internal pure returns (bytes32, uint256) {
        bytes32 digest = keccak256(
            abi.encodePacked(exposureReportID, timestamp)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return (r, uint256(s) | ((uint256(v) - 27) << 255));
    }

    function testReportFutureExposure() public {
        (bytes32 r1, uint256 s1) = signOffExposureReport(
            bytes32(uint256(123)),
            100,
            1
        );
        (bytes32 r2, uint256 s2) = signOffExposureReport(
            bytes32(uint256(123)),
            100,
            2
        );
        (bytes32 r3, uint256 s3) = signOffExposureReport(
            bytes32(uint256(123)),
            100,
            3
        );
        (bytes32 r4, uint256 s4) = signOffExposureReport(
            bytes32(uint256(123)),
            100,
            4
        );

        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            100,
            [r1, r2, r3],
            [s1, s2, s3]
        );
        vm.warp(99);
        vm.startPrank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        tcktSigners.approveSignerNode(vm.addr(2));
        tcktSigners.approveSignerNode(vm.addr(3));
        tcktSigners.approveSignerNode(vm.addr(4));
        vm.stopPrank();
        tckt.reportExposure(
            bytes32(uint256(123)),
            100,
            [r1, r2, r3],
            [s1, s2, s3]
        );
    }

    function testReportExposure() public {
        vm.startPrank(OYLAMA);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(100 + 10 * i);
            tcktSigners.approveSignerNode(vm.addr(i));
        }
        vm.stopPrank();

        (bytes32 r1, uint256 s1) = signOffExposureReport(
            bytes32(uint256(123)),
            130,
            1
        );
        (bytes32 r2, uint256 s2) = signOffExposureReport(
            bytes32(uint256(123)),
            130,
            2
        );
        (bytes32 r3, uint256 s3) = signOffExposureReport(
            bytes32(uint256(123)),
            130,
            3
        );
        (bytes32 r4, uint256 s4) = signOffExposureReport(
            bytes32(uint256(123)),
            130,
            4
        );
        vm.warp(140);
        vm.startPrank(OYLAMA);
        for (uint256 i = 1; i < 10; ++i) {
            tcktSigners.slashSignerNode(vm.addr(i));
        }
        vm.stopPrank();
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [r1, r3, r3],
            [s1, s3, s3]
        );
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [r1, r3, r1],
            [s1, s3, s1]
        );
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [r1, r1, r3],
            [s1, s1, s3]
        );
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [r1, r2, r4],
            [s1, s2, s4]
        );
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [r1, r2, r3],
            [s1, s2, s3]
        );
    }
}
