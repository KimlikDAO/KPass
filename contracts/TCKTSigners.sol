// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {END_TS_MASK, IDIDSigners} from "./IDIDSigners.sol";
import {IERC20} from "interfaces/IERC20.sol";
import {OYLAMA, TCKO_ADDR} from "interfaces/Addresses.sol";

/**
 * The contract by which KimlikDAO (i.e., TCKO holders) manage signer nodes.
 *
 * An evm address may be in one of the 4 states:
 *
 *   O: Never been a signer before.
 *   S: Staked the required amount, and is an active signer.
 *   U: A signer started the unstake process, and is no longer a valid signer,
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
contract TCKTSigners is IDIDSigners, IERC20 {
    event SignerNodeJoin(address indexed signer, uint256 timestamp);
    event SignerNodeLeave(address indexed signer, uint256 timestamp);
    event SignerNodeSlash(address indexed signer, uint256 slashedAmount);
    event StakingDepositChange(uint48 stakeAmount);
    event SignersNeededChange(uint256 signersCount);

    /**
     * The amount of TCKOs a node must stake before they can be voted as a
     * signer node. Note approving this amount for staking is a necessary first
     * step to be a signer, but not nearly sufficient. The signer node operator
     * is vetted by the DAO and voted for approval.
     *
     * The initial value is 1M TCKOs and the value is determined by DAO vote
     * thereafter via the `setStakingDeposit()` method.
     */
    uint256 public stakingDeposit = 1e12;

    /**
     * The minimum number of valid signer node signatures needed for a
     * validator to consider an `InfoSection` as valid.
     */
    uint256 public signersNeeded = 3;

    /**
     * The cumulative rate calculations are done as a multiple of this 80-bit
     * number and then divided by it at the end of the calculation. This
     * minimizes rounding errors, especially for numbers with prime factors
     * 2, 5, 3, 7, which we care about the most.
     */
    uint256 constant CUM_RATE_MULTIPLIER = (10**15) * (3**10) * (7**5);

    /**
     * Maps a jointDeposit event number to a bitpacked struct.
     *
     * cumRate: How many TCKOs may be withdrawn for every CUM_RATE_MULTIPLIER
     *          many TCKOs staked at the very beginning of this contract. While
     *          this tracks the cumulative rate for the initial signers, any
     *          other signer's cumulative rate can be calculated as a difference
     *          of two cumRate's. See `balanceOf()`.
     * timestamp: The block.timestamp of the block where the jointDeposit
     *            occurred.
     *
     * |--  cumRate --|---- timestamp ----|
     * |--   192    --|----    64     ----|
     *
     */
    mapping(uint256 => uint256) private jointDeposits;

    /**
     * The number of items in the `jointDeposits` mapping.
     */
    uint256 private jointDepositCount;

    /**
     * Maps and evm address to the signerInfo struct. See `IDIDSigners`.
     */
    mapping(address => uint256) public override signerInfo;

    /**
     * Sum of initial deposits of active signers.
     */
    uint256 private signerDepositBalance;

    ///////////////////////////////////////////////////////////////////////////
    //
    // TCKO-st token interface
    //
    ///////////////////////////////////////////////////////////////////////////

    function name() external pure override returns (string memory) {
        return "Staked TCKO";
    }

    function symbol() external pure override returns (string memory) {
        return "TCKO-st";
    }

    function decimals() external pure override returns (uint8) {
        return 6;
    }

    function totalSupply() external view override returns (uint256) {
        return IERC20(TCKO_ADDR).balanceOf(address(this));
    }

    /**
     * Returns the TCKO-st balance of a given address.
     *
     * Note the balance of an account may increase without ever a `Transfer`
     * event firing for this account. This happens after a `jointDeposit()`
     * or a slasing event, which distributes all the slashed TCKOs to active
     * signers proportional to their initial stake.
     *
     * @param addr Address of the account whose balance is queried.
     * @return The amount of TCKO-st tokens the address has.
     */
    function balanceOf(address addr) public view returns (uint256) {
        uint256 info = signerInfo[addr];
        unchecked {
            if (info & END_TS_MASK != 0) return info >> 192;
            uint256 startTs = uint64(info);
            uint256 n = jointDepositCount;
            uint256 r = n;

            for (uint256 l = 0; l < r; ) {
                uint256 m = r - ((r - l) >> 1);
                if (uint64(jointDeposits[m]) > startTs) r = m - 1;
                else l = m;
            }
            // Here we are using the fact that
            //   n > r => jointDeposits[n].timestamp > jointDeposits[r].timestamp
            uint256 cumulativeRate = r == 0
                ? jointDeposits[n]
                : jointDeposits[n] - jointDeposits[r];
            return
                (uint64(info >> 64) *
                    (CUM_RATE_MULTIPLIER + (cumulativeRate >> 64))) /
                CUM_RATE_MULTIPLIER;
        }
    }

    /**
     * The amount of TCKOs a signer initially deposited.
     *
     * Note depending of the status of the signer, these TCKOs may have been
     * withdrawn, increased or even completely slashed.
     *
     * @param addr A signer node address
     * @return The amount of TCKOs the signer deposited.
     */
    function depositBalanceOf(address addr) external view returns (uint256) {
        return uint64(signerInfo[addr] >> 64);
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure override returns (bool) {
        return false;
    }

    function allowance(address, address)
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return false;
    }

    /**
     * Deposits an amount of TCKOs to each signer proportional to their initial
     * TCKO stake.
     *
     * The sender must have approved this amount of TCKOs for use by the
     * TCKTSigners contract beforehand.
     *
     * @param amount The amount to deposit to signers
     */
    function jointDeposit(uint256 amount) external {
        IERC20(TCKO_ADDR).transferFrom(msg.sender, address(this), amount);
        unchecked {
            uint256 n = jointDepositCount;
            uint256 cumRate = jointDeposits[n] >> 64;
            jointDeposits[n + 1] =
                ((((CUM_RATE_MULTIPLIER * amount) / signerDepositBalance) +
                    cumRate) << 64) |
                block.timestamp;
            jointDepositCount = n + 1;
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Parameters to be adjusted by the DAO vote.
    //
    ///////////////////////////////////////////////////////////////////////////

    /**
     * Sets the TCKO amount required to qualify for the signer selection.
     *
     * Can only be set by the DAO vote, that is, the `OYLAMA` contract.
     *
     * Note the existing signers are not affected by a stakingDeposit change;
     * only new signers are subjected to the new staking amount.
     *
     * @param stakeAmount the amount required to be a signer node.
     */
    function setStakingDeposit(uint48 stakeAmount) external {
        require(msg.sender == OYLAMA);
        stakingDeposit = stakeAmount;
        emit StakingDepositChange(stakeAmount);
    }

    /**
     * Sets the number of valid signatures needed before an `InfoSection` is
     * deemed valid by the validators.
     *
     * Can only be set by the DAO vote, that is, the `OYLAMA` contract.
     *
     * @param signersCount the amount of valid signatures needed.
     */
    function setSignersNeeded(uint256 signersCount) external {
        require(msg.sender == OYLAMA);
        signersNeeded = signersCount;
        emit SignersNeededChange(signersCount);
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Signer node management functionality.
    //
    ///////////////////////////////////////////////////////////////////////////

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
            signerDepositBalance += stakeAmount;
            signerInfo[addr] = (stakeAmount << 64) | block.timestamp;
        }
        emit SignerNodeJoin(addr, block.timestamp);
        emit Transfer(address(this), addr, stakeAmount);
    }

    /**
     * A signer node may unstake their balance at any time they wish; doing so
     * removes their address from the valid signer list immediately.
     *
     * They can get their portion of the TCKOs back by calling the `withdraw()`
     * method after 30 days.
     *
     *   S ----`unstake()`----------------> U
     *
     */
    function unstake() external {
        uint256 info = signerInfo[msg.sender];
        // Ensure that `state(msg.sender) == S`.
        require(info != 0 && (info & END_TS_MASK == 0));
        unchecked {
            uint256 toWithdraw = balanceOf(msg.sender);
            uint256 deposited = uint64(info >> 64);
            signerDepositBalance -= deposited;
            signerInfo[msg.sender] =
                (toWithdraw << 192) |
                (block.timestamp << 128) |
                info;
        }
        emit SignerNodeLeave(msg.sender, block.timestamp);
    }

    /**
     * Returns back the staked TCKOs (plus excess) to its owner.
     * May only be called 30 days after an `unstake()`.
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
            signerInfo[msg.sender] = uint192(info);
            IERC20(TCKO_ADDR).transfer(msg.sender, toWithdraw);
            emit Transfer(msg.sender, address(this), toWithdraw);
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
        uint256 info = signerInfo[addr];
        unchecked {
            uint256 slashAmount = balanceOf(addr);
            uint256 signerBalanceLeft = signerDepositBalance;
            // The case `state(addr) == S`
            if (info != 0 && info & END_TS_MASK == 0) {
                signerInfo[addr] = (block.timestamp << 128) | info;
                signerBalanceLeft -= uint64(info >> 64);
                signerDepositBalance = signerBalanceLeft;
            } else {
                // The case `state(addr) == U`
                require(info >> 192 != 0);
                signerInfo[addr] = uint192(info); // Zero-out toWithdraw
            }
            uint256 n = jointDepositCount;
            uint256 cumRate = jointDeposits[n] >> 64;
            jointDeposits[n + 1] =
                ((((CUM_RATE_MULTIPLIER * slashAmount) / signerBalanceLeft) +
                    cumRate) << 64) |
                block.timestamp;
            jointDepositCount = n + 1;

            emit SignerNodeSlash(addr, slashAmount);
            emit SignerNodeLeave(addr, block.timestamp);
            emit Transfer(addr, address(this), slashAmount);
        }
    }
}
