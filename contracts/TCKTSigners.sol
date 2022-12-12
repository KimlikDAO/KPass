// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20} from "interfaces/IERC20.sol";
import {OYLAMA, TCKO_ADDR, TCKT_SIGNERS} from "interfaces/Addresses.sol";

/**
 * Contract for managing, rewarding, and slashing TCKT signer nodes.
 *
 * @author KimlikDAO
 */
contract TCKTSigners {
    event SignerNodeJoin(address indexed signer, uint256 timestamp);
    event SignerNodeLeave(address indexed signer, uint256 timestamp);
    event SignerNodeSlash(
        address indexed signer,
        uint256 slashedAmount,
        uint256 timestamp
    );
    event StakingDepositChange(uint48 stakeAmount);

    uint256 public stakingDeposit = 2e12;

    uint256 public totalExcess;

    uint256 private constant END_TIMESTAMP_MASK =
        uint256(type(uint64).max) << 128;

    // `signerInfo` layout:
    // |-- withdraw --|--  endTs --|-- deposit --|-- startTs --|
    // |--   64     --|--   64   --|--   64    --|--   64    --|
    mapping(address => uint256) public signerInfo;

    /**
     * Sets the TCKO amount required to be eligible to become a signer node.
     * Can only be set by `OYLAMA`.
     *
     * @param stakeAmount the amount required to be a signer node
     */
    function setStakingDeposit(uint48 stakeAmount) external {
        require(msg.sender == OYLAMA);
        stakingDeposit = stakeAmount;
        emit StakingDepositChange(stakeAmount);
    }

    /**
     * Marks a node as a validator as of the current blocktime, collecting
     * their staking deposit. The signer candidate must have approve this
     * contract for `stakingDeposit` TCKOs beforehand.
     *
     * @param addr Address of a node to be added to validator list.
     */
    function approveSignerNode(address addr) external {
        require(msg.sender == OYLAMA);
        require(signerInfo[addr] == 0);
        uint256 stakeAmount = stakingDeposit;
        IERC20(TCKO_ADDR).transferFrom(addr, TCKT_SIGNERS, stakeAmount);
        unchecked {
            signerInfo[addr] = (stakeAmount << 64) | block.timestamp;
        }
        emit SignerNodeJoin(addr, block.timestamp);
    }

    function unstake() external {
        uint256 info = signerInfo[msg.sender];
        require(info != 0 && (info & END_TIMESTAMP_MASK == 0));
        uint256 stakeAmount = (info >> 64) & type(uint64).max;
        uint256 totalStaked = IERC20(TCKO_ADDR).balanceOf(TCKT_SIGNERS);
        uint256 toWithdraw = (stakeAmount * totalStaked) /
            (totalStaked - totalExcess);
        signerInfo[msg.sender] =
            (toWithdraw << 192) |
            (block.timestamp << 128) |
            info;
        emit SignerNodeLeave(msg.sender, block.timestamp);
    }

    function withdraw() external {
        uint256 info = signerInfo[msg.sender];
        uint256 endTs = ((info >> 128) & type(uint64).max);
        assert(endTs != 0 && block.timestamp > endTs + 30 days);
        uint256 toWithdraw = info >> 192;
        uint256 stakeAmount = (info >> 64) & type(uint64).max;
        signerInfo[msg.sender] = info & type(uint128).max;
        if (toWithdraw > stakeAmount) totalExcess -= toWithdraw - stakeAmount;
        IERC20(TCKO_ADDR).transfer(msg.sender, toWithdraw);
    }

    /**
     * Bans a validator as of the current block time.
     *
     * @param addr             Address of the node to be banned from being
     *                         a validator.
     */
    function slashSignerNode(address addr) external {
        require(msg.sender == OYLAMA);
        unchecked {
            uint256 info = signerInfo[addr];
            require(info & END_TIMESTAMP_MASK == 0);
            uint256 stakeAmount = (info >> 64) & type(uint64).max;
            totalExcess += stakeAmount;
            signerInfo[addr] =
                (block.timestamp << 128) |
                (info & type(uint64).max);
            emit SignerNodeSlash(addr, stakeAmount, block.timestamp);
            emit SignerNodeLeave(addr, block.timestamp);
        }
    }
}
