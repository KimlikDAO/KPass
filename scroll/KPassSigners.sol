// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "interfaces/erc/IERC20.sol";
import {
    IDIDSigners,
    IDIDSignersExposureReport,
    SignerInfo,
    SignerInfoFrom
} from "interfaces/kimlikdao/IDIDSigners.sol";
import {KDAO as KDAO_ADDR, KPASS_SIGNERS, VOTING} from "interfaces/kimlikdao/addresses.sol";
import {Signature} from "interfaces/types/Signature.sol";
import {uint128x2} from "interfaces/types/uint128x2.sol";

IERC20 constant KDAO = IERC20(KDAO_ADDR);

/**
 * The contract by which KimlikDAO (i.e., KDAO holders) manage signer nodes.
 *
 * An evm address may be in one of the 4 states:
 *
 *   O: Never been a signer before.
 *   S: Staked the required amount, and is an active signer.
 *   U: A signer started the unstake process, and is no longer a valid signer,
 *      but hasn't collected their staked KDAOs (plus excess) yet.
 *   F: A former signer which the `KPassSigners` contract does not owe any
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
contract KPassSigners is IDIDSigners, IDIDSignersExposureReport, IERC20 {
    event SignerNodeJoin(address indexed signer, uint256 timestamp);
    event SignerNodeLeave(address indexed signer, uint256 timestamp);
    event SignerNodeSlash(address indexed signer, uint256 slashedAmount);
    event StakingDepositChange(uint48 stakeAmount);
    event SignerCountNeededChange(uint256 signerCount);
    event SignerStakeNeededChange(uint256 signerStake);

    /**
     * The amount of KDAOs a node must stake before they can be voted as a
     * signer node. Note approving this amount for staking is a necessary first
     * step to be a signer, but not nearly sufficient. The signer node operator
     * is vetted by the DAO and voted for approval.
     *
     * The initial value is 25K KDAOs and the value is determined by the `VOTING`
     * contract thereafter via the `setStakingDeposit()` method.
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
     * cumRate: How many KDAOs may be withdrawn for every CUM_RATE_MULTIPLIER
     *          many KDAOs staked at the very beginning of this contract. While
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
    // KDAO-st token interface
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
        return KDAO.balanceOf(address(this));
    }

    /**
     * Returns the KDAO-st balance of a given address.
     *
     * Note the balance of an account may increase without ever a `Transfer`
     * event firing for this account. This happens after a `jointDeposit()`
     * or a slasing event, which distributes all the slashed KDAOs to active
     * signers proportional to their initial stake.
     *
     * @param addr Address of the account whose balance is queried.
     * @return The amount of KDAO-st tokens the address has.
     */
    function balanceOf(address addr) public view returns (uint256) {
        SignerInfo info = signerInfo[addr];
        if (info.isZero()) return 0;
        if (info.hasEndTs()) return info.withdraw();
        uint256 startTs = info.startTs();
        uint256 n = jointDepositCount;
        uint256 r = n;
        unchecked {
            for (uint256 l = 0; l < r;) {
                uint256 m = r - ((r - l) >> 1);
                if (uint64(jointDeposits[m]) > startTs) r = m - 1;
                else l = m;
            }
            // Here we are using the fact that
            //   n > r => jointDeposits[n].timestamp > jointDeposits[r].timestamp
            uint256 cumulativeRate = r == 0 ? jointDeposits[n] : jointDeposits[n] - jointDeposits[r];
            return (info.deposit() * (CUM_RATE_MULTIPLIER + (cumulativeRate >> 64)))
                / CUM_RATE_MULTIPLIER;
        }
    }

    /**
     * The amount of KDAOs a signer initially deposited.
     *
     * Note depending of the status of the signer, these KDAOs may have been
     * withdrawn, increased or even completely slashed.
     *
     * @param addr A signer node address
     * @return The amount of KDAOs the signer deposited.
     */
    function depositBalanceOf(address addr) external view returns (uint256) {
        return signerInfo[addr].deposit();
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
     * Deposits an amount of KDAOs to each signer proportional to their initial
     * KDAO stake.
     *
     * The sender must have approved this amount of KDAOs for use by the
     * KimlikDAOPassSigners contract beforehand.
     *
     * @param amount The amount to deposit to signers
     */
    function jointDeposit(uint256 amount) external {
        KDAO.transferFrom(msg.sender, address(this), amount);
        unchecked {
            uint256 n = jointDepositCount;
            uint256 cumRate = jointDeposits[n] >> 64;
            jointDeposits[n + 1] = (
                (((CUM_RATE_MULTIPLIER * amount) / signerDepositBalance) + cumRate) << 64
            ) | block.timestamp;
            jointDepositCount = n + 1;
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Parameters to be adjusted by the `VOTING` contract
    //
    ///////////////////////////////////////////////////////////////////////////

    /**
     * Sets the KDAO amount required to qualify for the signer selection.
     *
     * Can only be set by the `VOTING` contract.
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
     * Can only be set by the `VOTING` contract.
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
     * Can only be set by the `VOTING` contract.
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
     * contract for `stakingDeposit` KDAOs beforehand.
     *
     *   O ----`approveSignerNode(addr)`--> S    Approve `stakingDeposit` KDAOs
     *
     * @param addr Address of a node to be added to validator list.
     */
    function approveSignerNode(address addr) external {
        require(msg.sender == VOTING);
        // Ensure that `state(addr) == O`.
        require(signerInfo[addr].isZero());
        uint256 stakeAmount = stakingDeposit;
        KDAO.transferFrom(addr, address(this), stakeAmount);
        unchecked {
            signerDepositBalance += stakeAmount;
        }
        signerInfo[addr] = SignerInfoFrom(
            uint256(keccak256(abi.encode(addr, block.timestamp))), stakeAmount, block.timestamp
        );
        emit SignerNodeJoin(addr, block.timestamp);
        emit Transfer(address(this), addr, stakeAmount);
    }

    /**
     * A signer node may unstake their balance at any time they wish; doing so
     * removes their address from the valid signer list immediately.
     *
     * They can get their portion of the KDAOs back by calling the `withdraw()`
     * method after 30 days.
     *
     *   S ----`unstake()`----------------> U
     *
     */
    function unstake() external {
        SignerInfo info = signerInfo[msg.sender];
        // Ensure that `state(msg.sender) == S`.
        require(!info.isZero() && !info.hasEndTs());
        uint256 toWithdraw = balanceOf(msg.sender);
        uint256 deposited = info.deposit();
        unchecked {
            signerDepositBalance -= deposited;
        }
        signerInfo[msg.sender] = info.addEndTs(block.timestamp).addWithdraw(toWithdraw);
        emit SignerNodeLeave(msg.sender, block.timestamp);
    }

    /**
     * Returns back the staked KDAOs (plus excess) to its owner.
     * May only be called 30 days after an `unstake()`.
     *
     *   U ----`withdraw()`---------------> F     30 days after `unstake()`
     *
     */
    function withdraw() external {
        SignerInfo info = signerInfo[msg.sender];
        uint256 endTs = info.endTs();
        uint256 toWithdraw = info.withdraw();
        // Ensure `state(msg.sender) == U`
        require(toWithdraw != 0 && endTs != 0);
        unchecked {
            require(block.timestamp > endTs + 30 days);
        }
        signerInfo[msg.sender] = info.clearWithdraw();
        KDAO.transfer(msg.sender, toWithdraw);
        emit Transfer(msg.sender, address(this), toWithdraw);
    }

    /**
     * Bans a validator as of the current block time.
     *
     *   S ----`slashSignerNode(addr)`----> F     Only by `VOTING` contract.
     *   U ----`shashSignerNode(addr)`----> F     Only by `VOTING` contract.
     *
     * @param addr             Address of the node to be banned from being
     *                         a validator.
     */
    function slashSignerNode(address addr) external {
        require(msg.sender == VOTING);
        SignerInfo info = signerInfo[addr];
        unchecked {
            uint256 slashAmount = balanceOf(addr);
            uint256 signerBalanceLeft = signerDepositBalance;
            // The case `state(addr) == S`
            if (!info.isZero() && !info.hasEndTs()) {
                signerInfo[addr] = info.addEndTs(block.timestamp);
                signerBalanceLeft -= info.deposit();
                signerDepositBalance = signerBalanceLeft;
            } else {
                // The case `state(addr) == U`
                signerInfo[addr] = info.clearWithdraw();
            }
            uint256 n = jointDepositCount;
            uint256 cumRate = jointDeposits[n] >> 64;
            jointDeposits[n + 1] = (
                (((CUM_RATE_MULTIPLIER * slashAmount) / signerBalanceLeft) + cumRate) << 64
            ) | block.timestamp;
            jointDepositCount = n + 1;

            emit SignerNodeSlash(addr, slashAmount);
            emit SignerNodeLeave(addr, block.timestamp);
            emit Transfer(addr, address(this), slashAmount);
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Signer authentication related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    function _authenticate3Sigs(
        bytes32 digest,
        uint128x2 stakeThresholdAndSignatureTs,
        Signature[3] calldata sigs
    ) internal view {
        uint256 signatureTs = stakeThresholdAndSignatureTs.lo();
        uint256 stake = 0;
        address[3] memory signer;
        unchecked {
            for (uint256 i = 0; i < 3; ++i) {
                signer[i] = ecrecover(
                    digest, sigs[i].yParityAndS.yParity(), sigs[i].r, sigs[i].yParityAndS.s()
                );
                SignerInfo info = signerInfo[signer[i]];
                uint256 endTs = info.endTs();
                stake += info.deposit();
                require(
                    !info.isZero() && info.startTs() <= signatureTs
                        && (endTs == 0 || signatureTs < endTs)
                );
            }
        }
        require(stake >= stakeThresholdAndSignatureTs.hi());
        require(signer[0] != signer[1] && signer[0] != signer[2] && signer[1] != signer[2]);
    }

    function _authenticate5Sigs(
        bytes32 digest,
        uint128x2 stakeThresholdAndSignatureTs,
        Signature[5] calldata sigs
    ) internal view {
        uint256 signatureTs = stakeThresholdAndSignatureTs.lo();
        uint256 stake = 0;
        address[5] memory signer;
        unchecked {
            for (uint256 i = 0; i < 5; ++i) {
                signer[i] = ecrecover(
                    digest, sigs[i].yParityAndS.yParity(), sigs[i].r, sigs[i].yParityAndS.s()
                );
                SignerInfo info = signerInfo[signer[i]];
                uint256 endTs = info.endTs();
                stake += info.deposit();
                require(
                    !info.isZero() && info.startTs() <= signatureTs
                        && (endTs == 0 || signatureTs < endTs)
                );
            }
        }
        require(stake >= stakeThresholdAndSignatureTs.hi());
        require(
            signer[0] != signer[1] && signer[0] != signer[2] && signer[0] != signer[3]
                && signer[0] != signer[4] && signer[1] != signer[2] && signer[1] != signer[3]
                && signer[1] != signer[4] && signer[2] != signer[3] && signer[2] != signer[4]
                && signer[3] != signer[4]
        );
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // HumanIDv1 related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    function getHumanIDv1Digest(bytes32 humanIDv1, uint256 signatureTs, bytes32 commitmentR)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                uint256(bytes32("\x19KimlikDAO hash\n")) | signatureTs,
                keccak256(abi.encodePacked(commitmentR, msg.sender)),
                humanIDv1
            )
        );
    }

    function authenticateHumanIDv1(
        bytes32 humanIDv1,
        uint128x2 stakeThresholdAndSignatureTs,
        bytes32 commitmentR,
        Signature[3] calldata sigs
    ) external view override returns (bool) {
        _authenticate3Sigs(
            getHumanIDv1Digest(humanIDv1, stakeThresholdAndSignatureTs.lo(), commitmentR),
            stakeThresholdAndSignatureTs,
            sigs
        );
        return true;
    }

    function authenticateHumanIDv1(
        bytes32 humanIDv1,
        uint128x2 stakeThresholdAndSignatureTs,
        bytes32 commitmentR,
        Signature[5] calldata sigs
    ) external view override returns (bool) {
        _authenticate5Sigs(
            getHumanIDv1Digest(humanIDv1, stakeThresholdAndSignatureTs.lo(), commitmentR),
            stakeThresholdAndSignatureTs,
            sigs
        );
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Exposure report related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    /**
     * @notice When a KPass holder gets their wallet private key exposed
     * they can either revoke their KPass themselves, or use social revoking.
     *
     * If they are unable to do either, they need to obtain a new KPass (to a
     * new address), with which they can file an exposure report via the
     * `reportExposure()` method. Doing so invalidates all KPasses across all
     * chains and all addresses they have obtained before the timestamp of this
     * newly obtained KPass.
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
     * @param sigs             Signer node signatures for the exposureReportID.
     */
    function reportExposure(
        bytes32 exposureReportID,
        uint256 signatureTs,
        Signature[3] calldata sigs
    ) external {
        bytes32 digest = keccak256(
            abi.encode(uint256(bytes32("\x19KimlikDAO hash\n")) | signatureTs, exposureReportID)
        );
        _authenticate3Sigs(digest, uint128x2.wrap(signatureTs), sigs);

        // Exposure report timestamp can only be incremented.
        require(exposureReported[exposureReportID] < signatureTs);
        exposureReported[exposureReportID] = signatureTs;
        emit ExposureReport(exposureReportID, signatureTs);
    }
}
