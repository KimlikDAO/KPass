// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "interfaces/IDIDSigners.sol";
import {IERC20} from "interfaces/IERC20.sol";
import {KDAO_ADDR, KPASS_SIGNERS, VOTING} from "interfaces/Addresses.sol";

/**
 * The contract by which KimlikDAO (i.e., KDAO holders) manage signer nodes.
 *
 * An evm address may be in one of the 4 states:
 *
 *   O: Never been a signer before.
 *   S: Staked the required amount, and is an active signer.
 *   U: A signer started the unstake process, and is no longer a valid signer,
 *      but hasn't collected their staked KDAOs (plus excess) yet.
 *   F: A former signer which the `KPASSSigners` contract does not owe any
 *      KDAOs to. A signer ends up in this state either by getting slashed
 *      or voluntarily unstaking and then collecting their KDAOs.
 *
 * The valid state transitions are as follows:
 *
 *   State Method                  End state  Prerequisite
 *   --------------------------------------------------------------------------
 *   O ----`approveSignerNode(addr)`--> S     Approve `stakingDeposit` KDAOs
 *   S ----`unstake()`----------------> U
 *   S ----`slashSignerNode(addr)`----> F     Only by protocol vote (VOTING)
 *   U ----`withdraw()`---------------> F     30 days after `unstake()`
 *   U ----`shashSignerNode(addr)`----> F     Only by protocol vote (VOTING)
 *
 * @author KimlikDAO
 */
contract KimlikDAOPassSigners is IDIDSigners, IERC20 {
    event SignerNodeJoin(address indexed signer, uint256 timestamp);
    event SignerNodeLeave(address indexed signer, uint256 timestamp);
    event SignerNodeSlash(address indexed signer, uint256 slashedAmount);
    event StakingDepositChange(uint48 stakeAmount);
    event SignerCountNeededChange(uint256 signerCount);
    event SignerStakeNeededChange(uint256 signerStake);

    /**
     * The amount of TCKOs a node must stake before they can be voted as a
     * signer node. Note approving this amount for staking is a necessary first
     * step to be a signer, but not nearly sufficient. The signer node operator
     * is vetted by the DAO and voted for approval.
     *
     * The initial value is 25K TCKOs and the value is determined by DAO vote
     * thereafter via the `setStakingDeposit()` method.
     */
    uint256 public stakingDeposit = 25_000e6;

    /**
     * The minimum number of valid signer node signatures needed for a
     * validator to consider a `did.Section` as valid.
     */
    uint256 public signerCountNeeded = 3;

    /**
     * The minimum amount of stake of the valid signer node signatures needed
     * for a validator to consider a `did.Section` as valid.
     */
    uint256 public signerStakeNeeded = 75_000e6;

    /**
     * The cumulative rate calculations are done as a multiple of this 80-bit
     * number and then divided by it at the end of the calculation. This
     * minimizes rounding errors, especially for numbers with prime factors
     * 2, 5, 3, 7, which we care about the most.
     */
    uint256 constant CUM_RATE_MULTIPLIER = (10 ** 15) * (3 ** 10) * (7 ** 5);

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
    mapping(address => SignerInfo) public override signerInfo;

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
        return "Staked KDAO";
    }

    function symbol() external pure override returns (string memory) {
        return "KDAO-st";
    }

    function decimals() external pure override returns (uint8) {
        return 6;
    }

    function totalSupply() external view override returns (uint256) {
        return IERC20(KDAO_ADDR).balanceOf(address(this));
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
        uint256 info = SignerInfo.unwrap(signerInfo[addr]);
        unchecked {
            if (info == 0) return 0;
            if (info & END_TS_MASK != 0) return uint48(info >> WITHDRAW_OFFSET);
            uint256 startTs = uint64(info);
            uint256 n = jointDepositCount;
            uint256 r = n;

            for (uint256 l = 0; l < r;) {
                uint256 m = r - ((r - l) >> 1);
                if (uint64(jointDeposits[m]) > startTs) r = m - 1;
                else l = m;
            }
            // Here we are using the fact that
            //   n > r => jointDeposits[n].timestamp > jointDeposits[r].timestamp
            uint256 cumulativeRate = r == 0 ? jointDeposits[n] : jointDeposits[n] - jointDeposits[r];
            return (uint48(info >> 64) * (CUM_RATE_MULTIPLIER + (cumulativeRate >> 64))) / CUM_RATE_MULTIPLIER;
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
        return uint48(SignerInfo.unwrap(signerInfo[addr]) >> 64);
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return false;
    }

    function allowance(address, address) external pure override returns (uint256) {
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
     * KPASSSigners contract beforehand.
     *
     * @param amount The amount to deposit to signers
     */
    function jointDeposit(uint256 amount) external {
        IERC20(KDAO_ADDR).transferFrom(msg.sender, address(this), amount);
        unchecked {
            uint256 n = jointDepositCount;
            uint256 cumRate = jointDeposits[n] >> 64;
            jointDeposits[n + 1] =
                ((((CUM_RATE_MULTIPLIER * amount) / signerDepositBalance) + cumRate) << 64) | block.timestamp;
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
        require(msg.sender == VOTING);
        stakingDeposit = stakeAmount;
        emit StakingDepositChange(stakeAmount);
    }

    /**
     * Sets the number of valid signatures needed before a `did.Section` is
     * deemed valid by the validators.
     *
     * Can only be set by the DAO vote, that is, the `OYLAMA` contract.
     *
     * @param signerCount the amount of valid signatures needed.
     */
    function setSignerCountNeeded(uint256 signerCount) external {
        require(msg.sender == VOTING);
        signerCountNeeded = signerCount;
        emit SignerCountNeededChange(signerCount);
    }

    /**
     * Sets the amount of valid signer stake needed before a `did.Section` is
     * deemed valid by the validators.
     *
     * Can only be set by the DAO vote, that is, the `OYLAMA` contract.
     *
     * @param signerStake the amount of valid signer stake needed.
     */
    function setSignerStakeNeeded(uint256 signerStake) external {
        require(msg.sender == VOTING);
        signerStakeNeeded = signerStake;
        emit SignerStakeNeededChange(signerStake);
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
        require(msg.sender == VOTING);
        // Ensure that `state(addr) == O`.
        require(SignerInfo.unwrap(signerInfo[addr]) == 0);
        uint256 stakeAmount = stakingDeposit;
        IERC20(KDAO_ADDR).transferFrom(addr, address(this), stakeAmount);
        unchecked {
            uint256 color = uint256(keccak256(abi.encode(addr, block.timestamp))) << 224;
            signerDepositBalance += stakeAmount;
            signerInfo[addr] = SignerInfo.wrap(color | (stakeAmount << 64) | block.timestamp);
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
        uint256 info = SignerInfo.unwrap(signerInfo[msg.sender]);
        // Ensure that `state(msg.sender) == S`.
        require(info != 0 && (info & END_TS_MASK == 0));
        unchecked {
            uint256 toWithdraw = balanceOf(msg.sender);
            uint256 deposited = uint48(info >> 64);
            signerDepositBalance -= deposited;
            signerInfo[msg.sender] =
                SignerInfo.wrap((toWithdraw << WITHDRAW_OFFSET) | (block.timestamp << END_TS_OFFSET) | info);
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
        uint256 info = SignerInfo.unwrap(signerInfo[msg.sender]);
        unchecked {
            uint256 endTs = uint64(info >> END_TS_OFFSET);
            uint256 toWithdraw = uint48(info >> WITHDRAW_OFFSET);
            // Ensure `state(msg.sender) == U`
            require(toWithdraw != 0 && endTs != 0);
            require(block.timestamp > endTs + 30 days);
            signerInfo[msg.sender] = SignerInfo.wrap(info & ~WITHDRAW_MASK);
            IERC20(KDAO_ADDR).transfer(msg.sender, toWithdraw);
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
        require(msg.sender == VOTING);
        uint256 info = SignerInfo.unwrap(signerInfo[addr]);
        unchecked {
            uint256 slashAmount = balanceOf(addr);
            uint256 signerBalanceLeft = signerDepositBalance;
            // The case `state(addr) == S`
            if (info != 0 && info & END_TS_MASK == 0) {
                signerInfo[addr] = SignerInfo.wrap((block.timestamp << END_TS_OFFSET) | info);
                signerBalanceLeft -= uint48(info >> 64);
                signerDepositBalance = signerBalanceLeft;
            } else {
                // The case `state(addr) == U`
                signerInfo[addr] = SignerInfo.wrap(info & ~WITHDRAW_MASK); // Zero-out toWithdraw
            }
            uint256 n = jointDepositCount;
            uint256 cumRate = jointDeposits[n] >> 64;
            jointDeposits[n + 1] =
                ((((CUM_RATE_MULTIPLIER * slashAmount) / signerBalanceLeft) + cumRate) << 64) | block.timestamp;
            jointDepositCount = n + 1;

            emit SignerNodeSlash(addr, slashAmount);
            emit SignerNodeLeave(addr, block.timestamp);
            emit Transfer(addr, address(this), slashAmount);
        }
    }

    function authenticateExposureReportID3Sigs(
        bytes32 exposureReportID,
        uint128x2 stakeThresholdAndSignatureTs,
        Signature[3] calldata sigs
    ) external view override {
        uint256 signatureTs = uint128(uint128x2.unwrap(stakeThresholdAndSignatureTs));
        bytes32 digest = keccak256(abi.encode(uint256(bytes32("\x19KimlikDAO hash\n")) | signatureTs, exposureReportID));
        uint256 stake = 0;
        address[3] memory signer;
        for (uint256 i = 0; i < 3; ++i) {
            signer[i] = ecrecover(
                digest,
                uint8(sigs[i].yParityAndS >> 255) + 27,
                sigs[i].r,
                bytes32(sigs[i].yParityAndS & ((1 << 255) - 1))
            );
            uint256 info = SignerInfo.unwrap(signerInfo[signer[i]]);
            uint256 endTs = uint64(info >> END_TS_OFFSET);
            stake += uint64(info >> DEPOSIT_OFFSET);
            require(info != 0 && uint64(info) <= signatureTs && (endTs == 0 || signatureTs < endTs));
        }
        uint256 stakeThreshold = uint128x2.unwrap(stakeThresholdAndSignatureTs) >> 128;
        require(stakeThreshold == 0 || stake <= stakeThreshold);
        require(signer[0] != signer[1] && signer[0] != signer[2] && signer[1] != signer[2]);
    }

    function authenticateHumanID3Sigs(
        bytes32 humanID,
        uint128x2 stakeThresholdAndSignatureTs,
        bytes32 commitmentR,
        Signature[3] calldata sigs
    ) external view override {
        uint256 signatureTs = uint128(uint128x2.unwrap(stakeThresholdAndSignatureTs));
        bytes32 digest = keccak256(
            abi.encode(
                uint256(bytes32("\x19KimlikDAO hash\n")) | signatureTs,
                keccak256(abi.encodePacked(commitmentR, msg.sender)),
                humanID
            )
        );
        uint256 stake = 0;
        address[3] memory signer;
        for (uint256 i = 0; i < 3; ++i) {
            signer[i] = ecrecover(
                digest,
                uint8(sigs[i].yParityAndS >> 255) + 27,
                sigs[i].r,
                bytes32(sigs[i].yParityAndS & ((1 << 255) - 1))
            );
            uint256 info = SignerInfo.unwrap(signerInfo[signer[i]]);
            uint256 endTs = uint64(info >> END_TS_OFFSET);
            stake += uint64(info >> DEPOSIT_OFFSET);
            require(info != 0 && uint64(info) <= signatureTs && (endTs == 0 || signatureTs < endTs));
        }
        uint256 stakeThreshold = uint128x2.unwrap(stakeThresholdAndSignatureTs) >> 128;
        require(stakeThreshold == 0 || stake <= stakeThreshold);
        require(signer[0] != signer[1] && signer[0] != signer[2] && signer[1] != signer[2]);
    }

    function authenticateHumanID5Sigs(
        bytes32 humanID,
        uint128x2 stakeThresholdAndSignatureTs,
        bytes32 commitmentR,
        Signature[5] calldata sigs
    ) external view override {
        uint256 signatureTs = uint128(uint128x2.unwrap(stakeThresholdAndSignatureTs));
        bytes32 digest = keccak256(
            abi.encode(
                uint256(bytes32("\x19KimlikDAO hash\n")) | signatureTs,
                keccak256(abi.encodePacked(commitmentR, msg.sender)),
                humanID
            )
        );
        uint256 stake = 0;
        address[5] memory signer;
        for (uint256 i = 0; i < 5; ++i) {
            signer[i] = ecrecover(
                digest,
                uint8(sigs[i].yParityAndS >> 255) + 27,
                sigs[i].r,
                bytes32(sigs[i].yParityAndS & ((1 << 255) - 1))
            );
            uint256 info = SignerInfo.unwrap(signerInfo[signer[i]]);
            uint256 endTs = uint64(info >> END_TS_OFFSET);
            stake += uint64(info >> DEPOSIT_OFFSET);
            require(info != 0 && uint64(info) <= signatureTs && (endTs == 0 || signatureTs < endTs));
        }
        uint256 stakeThreshold = uint128x2.unwrap(stakeThresholdAndSignatureTs) >> 128;
        require(stakeThreshold == 0 || stake <= stakeThreshold);
        require(
            signer[0] != signer[1] && signer[0] != signer[2] && signer[0] != signer[3] && signer[0] != signer[4]
                && signer[1] != signer[2] && signer[1] != signer[3] && signer[1] != signer[4] && signer[2] != signer[3]
                && signer[2] != signer[4] && signer[3] != signer[4]
        );
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Exposure report related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    /**
     * @notice When a KPASS holder gets their wallet private key exposed
     * they can either revoke their KPASS themselves, or use social revoking.
     *
     * If they are unable to do either, they need to obtain a new KPASS (to a
     * new address), with which they can file an exposure report via the
     * `reportExposure()` method. Doing so invalidates all KPASSs across all
     * chains and all addresses they have obtained before the timestamp of this
     * newly obtained KPASS.
     */
    event ExposureReport(bytes32 indexed exposureReportID, uint256 timestamp);

    /**
     * Maps a `exposureReportID` to a reported exposure timestamp, or zero if
     * no exposure has been reported.
     */
    mapping(bytes32 => uint256) public exposureReported;

    /**
     * Adds an `exposureReportID` to the exposed list.
     *
     * A nonce is not needed since the `exposureReported[exposureReportID]`
     * value can only be incremented.
     *
     * @param exposureReportID of the person whose wallet keys were exposed.
     * @param signatureTs      of the exposureReportID signatures.
     * @param signatures       Signer node signatures for the exposureReportID.
     */
    function reportExposure(bytes32 exposureReportID, uint256 signatureTs, Signature[3] calldata signatures) external {
        IDIDSigners(KPASS_SIGNERS).authenticateExposureReportID3Sigs(
            exposureReportID, uint128x2.wrap(signatureTs), signatures
        );
        // Exposure report timestamp can only be incremented.
        require(exposureReported[exposureReportID] < signatureTs);
        exposureReported[exposureReportID] = signatureTs;
        emit ExposureReport(exposureReportID, signatureTs);
    }
}
