// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import {
    IProtocolFund,
    RedeemInfo,
    REDEEM_INFO_AMOUNT_OFFSET,
    REDEEM_INFO_SUPPLY_OFFSET
} from "interfaces/IProtocolFund.sol";
import {KimlikDAOPassSigners} from "contracts/KimlikDAOPassSigners.sol";
import {MockERC20Permit} from "interfaces/testing/MockTokens.sol";
import {MockProtocolFund} from "interfaces/testing/MockProtocolFund.sol";
import {MockProtocolFundV1} from "interfaces/testing/MockProtocolFundV1.sol";
import {KimlikDAOPass, Signature} from "contracts/KimlikDAOPass.sol";

contract KimlikDAOPassIntegrationTest is Test {
    MockERC20Permit private kdao;
    KimlikDAOPass private kpass;
    KimlikDAOPassSigners private kpassSigners;

    event ExposureReport(bytes32 indexed exposureReportID, uint256 timestamp);

    function setUp() public {
        vm.prank(KPASS_DEPLOYER);
        kpass = new KimlikDAOPass();
        vm.prank(KPASS_SIGNERS_DEPLOYER);
        kpassSigners = new KimlikDAOPassSigners();
        vm.prank(KDAO_DEPLOYER);
        kdao = new MockERC20Permit("KimlikDAO", "KDAO", 6);

        assertEq(address(kpass), KPASS_ADDR);
        assertEq(address(kpassSigners), KPASS_SIGNERS);
        assertEq(address(kdao), KDAO_ADDR);

        for (uint256 i = 1; i <= 10; ++i) {
            vm.startPrank(vm.addr(i));
            kdao.mint(200_000e6);
            kdao.approve(address(kpassSigners), 2e11);
            vm.stopPrank();
        }
    }

    function signOffExposureReport(bytes32 exposureReportID, uint256 timestamp, uint256 signerKey)
        internal
        pure
        returns (Signature memory sig)
    {
        bytes32 digest = keccak256(abi.encode(uint256(bytes32("\x19KimlikDAO hash\n")) | timestamp, exposureReportID));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        sig.r = r;
        sig.yParityAndS = ((uint256(v) - 27) << 255) | uint256(s);
    }

    function testReportFutureExposure() public {
        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 100, 1),
            signOffExposureReport(bytes32(uint256(123)), 100, 2),
            signOffExposureReport(bytes32(uint256(123)), 100, 3),
            signOffExposureReport(bytes32(uint256(123)), 100, 4)
        ];
        vm.warp(99);
        vm.startPrank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));
        kpassSigners.approveSignerNode(vm.addr(2));
        kpassSigners.approveSignerNode(vm.addr(3));
        kpassSigners.approveSignerNode(vm.addr(4));
        vm.stopPrank();
        kpassSigners.reportExposure(bytes32(uint256(123)), 100, [sigs[0], sigs[1], sigs[2]]);
    }

    function testReportExposure() public {
        vm.startPrank(VOTING);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(100 + 10 * i);
            kpassSigners.approveSignerNode(vm.addr(i));
        }
        vm.stopPrank();

        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 130, 1),
            signOffExposureReport(bytes32(uint256(123)), 130, 2),
            signOffExposureReport(bytes32(uint256(123)), 130, 3),
            signOffExposureReport(bytes32(uint256(123)), 130, 4)
        ];
        vm.warp(140);
        vm.startPrank(VOTING);
        for (uint256 i = 1; i < 10; ++i) {
            kpassSigners.slashSignerNode(vm.addr(i));
        }
        vm.stopPrank();
        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[1], sigs[0]]);
        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[1], sigs[1]]);
        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[0], sigs[1]]);
        vm.expectEmit(true, true, true, true, address(kpassSigners));
        emit ExposureReport(bytes32(uint256(123)), uint256(130));
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[1], sigs[2]]);
    }

    function testReportBySlashedSigner() external {
        vm.warp(1000);
        vm.startPrank(VOTING);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(1000 + 10 * i);
            kpassSigners.approveSignerNode(vm.addr(i));
        }

        vm.warp(1110);
        for (uint256 i = 1; i < 10; ++i) {
            kpassSigners.slashSignerNode(vm.addr(i));
        }
        vm.stopPrank();

        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 1111, 1),
            signOffExposureReport(bytes32(uint256(123)), 1111, 2),
            signOffExposureReport(bytes32(uint256(123)), 1111, 3),
            signOffExposureReport(bytes32(uint256(123)), 1111, 4)
        ];

        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 1111, [sigs[0], sigs[1], sigs[2]]);
    }

    function testSweepNativeToken() external {
        vm.startPrank(PROTOCOL_FUND_DEPLOYER);
        IProtocolFund protocolFund = IProtocolFund(address(new MockProtocolFund()));
        new MockProtocolFundV1();
        vm.stopPrank();

        assertEq(address(protocolFund), PROTOCOL_FUND);

        vm.deal(vm.addr(1), 0.1e18);
        vm.prank(vm.addr(1));
        // Overpay by 0.005.
        kpass.create{value: 0.08e18}(0x9991);

        vm.prank(address(0xDEAD));
        kpass.sweepNativeToken();

        assertEq(PROTOCOL_FUND.balance, 0.08e18);

        vm.deal(vm.addr(2), 0.2e18);
        vm.prank(vm.addr(2));
        kpass.create{value: 0.075e18}(0x9992);
        kpass.create{value: 0.075e18}(0x99922);

        vm.prank(address(0xACC));
        kpass.sweepNativeToken();

        assertEq(PROTOCOL_FUND.balance, 0.23e18);

        vm.prank(PROTOCOL_FUND);
        protocolFund.redeem(
            RedeemInfo.wrap(
                (uint256(1) << REDEEM_INFO_AMOUNT_OFFSET) | (uint256(1) << REDEEM_INFO_SUPPLY_OFFSET)
                    | uint160(vm.addr(3))
            )
        );

        assertEq(vm.addr(3).balance, 0.23e18);
    }
}
