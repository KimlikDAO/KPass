// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DEPOSIT_MASK, END_TS_MASK, IDIDSigners} from "./IDIDSigners.sol";
import {IERC20} from "interfaces/IERC20.sol";
import {OYLAMA, TCKO_ADDR} from "interfaces/Addresses.sol";

/**
 * The contract by which KimlikDAO (i.e., TCKO holders) manage signer nodes.
 *
 * An evm address may be in one of the 4 states:
 *
 *   O: Never been a signer before.
 *   S: Staked the required amount, and is an active signer.
 *   U: A signer started the unstake process, and no longer a valid signer,
 *      but hasn't collected their staked TCKOs (plus excess) yet.
 *   F: A former signer which the `TCKTSigners` contract does not owe any
 *      TCKOs to. A signer ends up in this state either by getting slashed
 *      or voluntarily unstaking and then collecting their TCKOs.
 *
 * The valid state transitions are as follows:
 *
 *   State Method                  End state  Prerequisite
 *   --------------------------------------------------------------------------
 *   O ----`approveSignerNode(addr)`--> S     Approve `stakingDeposit` TCKOs
 *   S ----`unstake()`----------------> U
 *   S ----`slashSignerNode(addr)`----> F     Only by DAO vote (OYLAMA)
 *   U ----`withdraw()`---------------> F     30 days after `unstake()`
 *   U ----`shashSignerNode(addr)`----> F     Only by DAO vote (OYLAMA)
 *
 * @author KimlikDAO
 */
contract TCKTSigners is IDIDSigners {
    event SignerNodeJoin(address indexed signer, uint256 timestamp);
    event SignerNodeLeave(address indexed signer, uint256 timestamp);
    event SignerNodeSlash(
        address indexed signer,
        uint256 slashedAmount,
        uint256 timestamp
    );
    event StakingDepositChange(uint48 stakeAmount);

    /**
     * The amount of TCKTs a node must stake before they can be voted as a
     * signer node. Note approving this amount for staking is a necessary first
     * step to be a signer, but nearly sufficient.
     *
     * The initial value is 1M TCKOs and the value is determined by DAO vote
     * thereafter via the `setStakingDeposit()` method.
     */
    uint256 public stakingDeposit = 1e12;

    /**
     * The total TCKOs of this contract minus the debt to be returned to the
     * signer nodes.
     *
     * The excess increases as signers get slashed and decreases as signers
     * unstake and collect their share of the excess.
     */
    uint256 public totalExcess;

    mapping(address => uint256) public override signerInfo;

    /**
     * Sets the TCKO amount required to be eligible to become a signer node.
     * Can only be set by `OYLAMA`.
     *
     * Note the existing signers are not affected by a stakingDeposit change;
     * only the new signers are subjected to the new staking amount.
     *
     * @param stakeAmount the amount required to be a signer node.
     */
    function setStakingDeposit(uint48 stakeAmount) external {
        require(msg.sender == OYLAMA);
        stakingDeposit = stakeAmount;
        emit StakingDepositChange(stakeAmount);
    }

    /**
     * Marks a node as a validator as of the current blocktime, collecting
     * their staking deposit. The signer candidate must have approved this
     * contract for `stakingDeposit` TCKOs beforehand.
     *
     *   O ----`approveSignerNode(addr)`--> S    Approve `stakingDeposit` TCKOs
     *
     * @param addr Address of a node to be added to validator list.
     */
    function approveSignerNode(address addr) external {
        require(msg.sender == OYLAMA);
        // Ensure that `state(addr) == O`.
        require(signerInfo[addr] == 0);
        uint256 stakeAmount = stakingDeposit;
        IERC20(TCKO_ADDR).transferFrom(addr, address(this), stakeAmount);
        unchecked {
            signerInfo[addr] = (stakeAmount << 64) | block.timestamp;
        }
        emit SignerNodeJoin(addr, block.timestamp);
    }

    /**
     * A signer node may unstake their deposit at any time they wish; doing so
     * removes their address from the valid signer list immediately.
     *
     * They can get their staked TCKOs back by calling the `withdraw()` method
     * after 30 days.
     *
     *   S ----`unstake()`----------------> U
     *
     */
    function unstake() external {
        uint256 info = signerInfo[msg.sender];
        // Ensure that `state(msg.sender) == S`.
        require(info != 0 && (info & END_TS_MASK == 0));
        unchecked {
            uint256 totalStaked = IERC20(TCKO_ADDR).balanceOf(address(this));
            uint256 toWithdraw = (uint64(info >> 64) * totalStaked) /
                (totalStaked - totalExcess);
            signerInfo[msg.sender] =
                (toWithdraw << 192) |
                (block.timestamp << 128) |
                info;
        }
        emit SignerNodeLeave(msg.sender, block.timestamp);
    }

    /**
     * This method returns back the staked TCKOs (plus excess) to its owner 30
     * days after the owner unstakes.
     *
     *   U ----`withdraw()`---------------> F     30 days after `unstake()`
     *
     */
    function withdraw() external {
        uint256 info = signerInfo[msg.sender];
        unchecked {
            uint256 endTs = uint64(info >> 128);
            uint256 toWithdraw = info >> 192;
            // Ensure `state(msg.sender) == U`
            require(toWithdraw != 0 && endTs != 0);
            require(block.timestamp > endTs + 30 days);
            uint256 stakeAmount = uint64(info >> 64);
            signerInfo[msg.sender] = uint192(info);
            if (toWithdraw > stakeAmount)
                totalExcess -= toWithdraw - stakeAmount;
            IERC20(TCKO_ADDR).transfer(msg.sender, toWithdraw);
        }
    }

    /**
     * Bans a validator as of the current block time.
     *
     *   S ----`slashSignerNode(addr)`----> F     Only by DAO vote (OYLAMA)
     *   U ----`shashSignerNode(addr)`----> F     Only by DAO vote (OYLAMA)
     *
     * @param addr             Address of the node to be banned from being
     *                         a validator.
     */
    function slashSignerNode(address addr) external {
        require(msg.sender == OYLAMA);
        unchecked {
            uint256 info = signerInfo[addr];
            uint256 stakeAmount = uint64(info >> 64);

            // The case `state(addr) == S`
            if (info & END_TS_MASK == 0) {
                signerInfo[addr] = (block.timestamp << 128) | info;
            } else {
                // The case `state(addr) == U`
                require(info >> 192 != 0);
                signerInfo[addr] = uint192(info); // Zero-out toWithdraw
            }
            totalExcess += stakeAmount;
            emit SignerNodeSlash(addr, stakeAmount, block.timestamp);
            emit SignerNodeLeave(addr, block.timestamp);
        }
    }
}
