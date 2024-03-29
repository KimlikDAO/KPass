// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {KPASS_DEPLOYER, KPASS_SIGNERS, PROTOCOL_FUND, VOTING} from "interfaces/Addresses.sol";
import {IDIDSigners, Signature, uint128x2} from "interfaces/IDIDSigners.sol";
import {IERC20, IERC20Permit} from "interfaces/IERC20Permit.sol";
import {IERC721} from "interfaces/IERC721.sol";

/**
 * @title KPASS: KimlikDAO Pass
 *
 * KPASS is a decentralized identifier (DID) NFT which can be minted by
 * interacting with the KimlikDAO protocol. To interact with the protocol,
 * one can use the reference dApp deployed at https://kimlikdao.org or run it
 * locally by cloning the repo https://github.com/KimlikDAO/dapp and following
 * the instructions therein.
 *
 * The contents of each KPASS is cryptographically committed to a single EVM
 * address, making it unusable from any other address.
 * KPASS implements most of the ERC-721 NFT interface excluding, notably, the
 * transfer-related methods, since KPASSs are non-transferrable.
 *
 * Minting
 * ========
 * One can mint a KPASS by using the various flavors of the `create()` method.
 * These methods differ in the payment type and whether a revoker list is
 * included. A discount is offerent for including a revoker list, which
 * increases security as explained below.
 *
 * Revoking
 * =========
 * A KPASS owner may call the `revoke()` method of a KPASS at any time to revoke
 * it, thereby making it unusable. This is useful, for example, when a user
 * gets their wallet private keys stolen.
 *
 * Social revoking
 * ================
 * When minting a KPASS, you can nominate 3-5 addresses as revokers, assign each
 * a weight and choose a revoke threshold. If enough of these addresses vote to
 * revoke the KPASS (with total weight at least the chosen threshold), it will
 * be revoked and become unusable.
 *
 * This feature is useful in the event that your wallet private keys are stolen
 * and, further, you no longer have access to them. In such circumstances, you
 * can inform the nominated revokers and request them to cast a revoke vote.
 *
 * To encourage setting up social revoke, a discount of 33% is offered
 * initially, and the discount rate is determined by the KDAO holder vote
 * thereafter.
 * The discount rate is set through the `updatePricesBulk()` method, which can
 * only be called by `VOTING`, the KimlikDAO voting contract.
 * (https://github.com/KimlikDAO/ProtocolFund)
 *
 * Exposure report
 * ================
 * In the case a KPASS holder
 *
 *   1) gets their private keys stolen, and
 *   2) lose access to the keys themselves, and
 *   3) did not set up social revoke when minting the KPASS,
 *
 * there is one final way of disabling the stolen KPASS. The victim mints a new
 * KPASS and submits the `exposureReport` that comes with it to the
 * `reportExposure()` method of this contract. Doing so will disable *all*
 * previous KPASSs across all chains belonging to this person. For convenience,
 * one may use the interface at https://kimlikdao.org/report to submit the
 * `exposureReport` to the KPASS contract.
 *
 * Modifying the revoker list
 * ===========================
 * One can add new revokers, increase the weight of existing revokers or reduce
 * the revoke threshold after minting their KPASS by invoking the corresponding
 * methods of this contract. Removing a revoker is not possible since it would
 * allow an attacker having access to user privates key to remove all revokers.
 *
 * Pricing and payments
 * =====================
 * The price of a KPASS is set by the `updatePrice()` or the `updatePricesBulk()`
 * methods, which can only be called by `VOTING`, the KimlikDAO voting
 * contract.
 *
 * Fees collected as an ERC-20 token are transferred directly to the
 * `PROTOCOL_FUND`, the KimlikDAO protocol funds and fees collected in the native
 * token are accumulated in this contract first and then swept to `PROTOCOL_FUND`
 * periodically. The sweep mechanism was put in place to minimize the gas cost
 * of minting a KPASS. The sweep is completely permissionless; anyone can call
 * the `sweepNativeToken()` to transfer the native token balance of this
 * contract over to `PROTOCOL_FUND`. Further, weekly sweeps are done by KimlikDAO
 * automation, covering the gas fee.
 *
 * @author KimlikDAO (https://kimlikdao.org)
 */
contract KimlikDAOPass is IERC721 {
    /**
     * Returns the KimlikDAO protocol IPFS handle (in compact form) of an
     * address or zero if the address does not have a KPASS.
     */
    mapping(address => uint256) public handleOf;

    function name() external pure override returns (string memory) {
        return "KimlikDAO Pass";
    }

    function symbol() external pure override returns (string memory) {
        return "KPASS";
    }

    /**
     * Returns the number of KPASSs in a given account, which can be 0 or 1.
     *
     * Each account can hold at most one KPASS, however a new KPASS can be minted
     * to the same address at any time replacing the previous one. While
     * obtaining a KPASS is subject to a KimlikDAO fee, subsequent updates can
     * be done by only paying the network fee.
     */
    function balanceOf(address addr) external view override returns (uint256) {
        return handleOf[addr] == 0 ? 0 : 1;
    }

    /**
     * Returns the URI of a KPASS with the given id (handle).
     *
     * @dev The handle of each KPASS is a compact representation of its
     * KimlikDAO protocol IPFS cid. Given the handle, the IPFS cid can be
     * obtained as
     *
     *     base58([0x12, 0x20, handle]).
     *
     * This method computes this value in a a gas efficient manner.
     */
    function tokenURI(uint256 id) external pure override returns (string memory) {
        unchecked {
            bytes memory toChar = bytes("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz");
            uint256 magic = 0x4e5a461f976ce5b9229582822e96e6269e5d6f18a5960a04480c6825748ba04;
            bytes memory out = "https://ipfs.kimlikdao.org/ipfs/Qm____________________________________________";
            out[77] = toChar[id % 58];
            id /= 58;
            for (uint256 p = 76; p > 34; --p) {
                uint256 t = id + (magic & 63);
                out[p] = toChar[t % 58];
                magic >>= 6;
                id = t / 58;
            }
            out[34] = toChar[id + 21];
            return string(out);
        }
    }

    /**
     * Returns whether a given ERC-165 interface is supported.
     *
     * Here we claim to support the full ERC-721 interface so that wallets
     * recognize KPASS as an NFT, even though we do not implement transfer
     * related methods since KPASSs are non-transferrable.
     *
     * See https://eips.ethereum.org/EIPS/eip-165 for more information.
     *
     * @param                  interfaceId to check support for.
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 interface ID for ERC165.
            || interfaceId == 0x80ac58cd // ERC165 interface ID for ERC721.
            || interfaceId == 0x5b5e139f; // ERC165 interface ID for ERC721Metadata.
    }

    /**
     * Creates a new KPASS and collects the fee in the native token.
     *
     * @param                  handle the compact encoding of the IPFS handle.
     */
    function create(uint256 handle) external payable {
        require(msg.value >= (priceIn[address(0)] >> 128));
        handleOf[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * Transfers the entire native token balance of this contract to
     * `PROTOCOL_FUND`.
     *
     * @dev To optimize the KPASS creation gas fees, we do not forward fees
     * collected in the networks native token to `PROTOCOL_FUND` in each KPASS
     * creation.
     *
     * Instead, the fees are accumulated in this contract until the following
     * method is called. The method is fully permissionless and can be invoked
     * by anyone. Further, KimlikDAO does weekly sweeps, again using this
     * method and covering the gas fee.
     *
     * @dev `PROTOCOL_FUND` has an empty `receive()` method therefore the
     * `transfer()` below should have enough gas to complete.
     */
    function sweepNativeToken() external {
        PROTOCOL_FUND.transfer(address(this).balance);
    }

    /**
     * Moves ERC-20 tokens sent to this address by accident to `PROTOCOL_FUND`.
     */
    function sweepToken(IERC20 token) external {
        token.transfer(PROTOCOL_FUND, token.balanceOf(address(this)));
    }

    /**
     * Creates a new KPASS with the given social revokers and collects the fee
     * in the native token.
     *
     * @param handle           IPFS handle of the persisted KPASS.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes. Further, the first
     *                         word contains the revokeThreshold in the
     *                         leftmost 64 bits.
     */
    function createWithRevokers(uint256 handle, uint256[5] calldata revokers) external payable {
        require(msg.value >= uint128(priceIn[address(0)]));
        handleOf[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
        _setRevokers(revokers);
    }

    /**
     * Creates a new KPASS collecting the fee in the provided `token`.
     *
     * This method works only with protocol approved tokens: the token must have
     * been approved and set a nonzero price by the KDAO holder vote beforehand.
     *
     * @param handle           IPFS handle of the persisted KPASS.
     * @param token            Contract address of an ERC-20 token.
     */
    function createWithTokenPayment(uint256 handle, IERC20 token) external {
        uint256 price = priceIn[address(token)] >> 128;
        require(price > 0);
        token.transferFrom(msg.sender, PROTOCOL_FUND, price);
        handleOf[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * Creates a KPASS and collects the fee in the provided `token` using the
     * provided ERC-2612 permit signature.
     *
     * The provided token has to be IERC20Permit, in particular, it needs to
     * support approval by signature.
     *
     * Note if a price change occurs between the moment the user signs off the
     * payment and this method is called, the method call will fail as the
     * signature will be invalid. However, the price changes happen at most
     * once a week and off peak hours by the KDAO holder vote.
     *
     * See https://eips.ethereum.org/EIPS/eip-2612 for more information on the
     * ERC-20 permit extension.
     *
     * @param handle           IPFS handle of the persisted KPASS.
     * @param deadlineAndToken Contract address of a IERC20Permit token and
     *                         the timestamp until which the payment
     *                         authorization is valid for.
     * @param signature        Signature authorizing the token spend.
     */
    function createWithTokenPermit(uint256 handle, uint256 deadlineAndToken, Signature calldata signature) external {
        IERC20Permit token = IERC20Permit(address(uint160(deadlineAndToken)));
        uint256 price = priceIn[address(token)] >> 128;
        require(price > 0);
        unchecked {
            token.permit(
                msg.sender,
                address(this),
                price,
                deadlineAndToken >> 160,
                uint8(signature.yParityAndS >> 255) + 27,
                signature.r,
                bytes32(signature.yParityAndS & ((1 << 255) - 1))
            );
        }
        token.transferFrom(msg.sender, PROTOCOL_FUND, price);
        handleOf[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @param handle           IPFS handle of the persisted KPASS.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes.
     * @param token            Contract address of a IERC20Permit token.
     */
    function createWithRevokersWithTokenPayment(uint256 handle, uint256[5] calldata revokers, IERC20 token) external {
        uint256 price = uint128(priceIn[address(token)]);
        require(price > 0);
        token.transferFrom(msg.sender, PROTOCOL_FUND, price);
        handleOf[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
        _setRevokers(revokers);
    }

    /**
     * @param handle           IPFS handle of the persisted KPASS.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes.
     * @param deadlineAndToken Contract address of a IERC20Permit token.
     * @param signature        Signature authorizing the token spend.
     */
    function createWithRevokersWithTokenPermit(
        uint256 handle,
        uint256[5] calldata revokers,
        uint256 deadlineAndToken,
        Signature calldata signature
    ) external {
        IERC20Permit token = IERC20Permit(address(uint160(deadlineAndToken)));
        uint256 price = uint128(priceIn[address(token)]);
        require(price > 0);
        unchecked {
            token.permit(
                msg.sender,
                address(this),
                price,
                deadlineAndToken >> 160,
                uint8(signature.yParityAndS >> 255) + 27,
                signature.r,
                bytes32(signature.yParityAndS & ((1 << 255) - 1))
            );
        }
        token.transferFrom(msg.sender, PROTOCOL_FUND, price);
        handleOf[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
        _setRevokers(revokers);
    }

    // keccak256(
    //     abi.encode(
    //         keccak256(
    //             "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    //         ),
    //         keccak256(bytes("KPASS")),
    //         keccak256(bytes("1")),
    //         0x144,
    //         0xcCc0a9b023177549fcf26c947edb5bfD9B230cCc
    //     )
    // );
    bytes32 public constant DOMAIN_SEPARATOR = 0xabb9acc56e2c9f970df08732f9102ae6836bd714edec2c9af31dedc648bb8e7b;

    // keccak256("CreateFor(uint256 handle)")
    bytes32 public constant CREATE_FOR_TYPEHASH = 0xe0b70ef26ac646b5fe42b7831a9d039e8afa04a2698e03b3321e5ca3516efe70;

    /**
     * Creates a KPASS on users behalf, covering the transaction fee.
     *
     * The user has to explicitly authorize the KPASS creation with the
     * `createSig` and the token payment with the `paymentSig`.
     *
     * The gas fee is paid by the transaction sender, which can be either
     * `VOTING` or `KPASS_DEPLOYER`. We restrict the method to these two
     * addresses since the intent of a signature request is not as clear as
     * that of a transaction and therefore a user may be tricked into creating
     * a KPASS with incorrect and invalid contents. Note this restriction is not
     * about KPASSs soundness; even if we made this method unrestricted, only the
     * account owner could have created a valid KPASS. Still, we do not want
     * users to be tricked into creating invalid KPASSs for whatever reason.
     *
     * @param handle           IPFS handle with which to create the KPASS.
     * @param createSig        Signature endorsing the KPASS creation.
     * @param deadlineAndToken The payment token and the deadline for the token
     *                         permit signature.
     * @param paymentSig       Token spend permission from the KPASS creator.
     */
    function createFor(
        uint256 handle,
        Signature calldata createSig,
        uint256 deadlineAndToken,
        Signature calldata paymentSig
    ) external {
        require(msg.sender == VOTING || msg.sender == KPASS_DEPLOYER);
        IERC20Permit token = IERC20Permit(address(uint160(deadlineAndToken)));
        uint256 price = priceIn[address(token)] >> 128;
        require(price > 0);
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(CREATE_FOR_TYPEHASH, handle)))
            );
            address signer = ecrecover(
                digest,
                uint8(createSig.yParityAndS >> 255) + 27,
                createSig.r,
                bytes32(createSig.yParityAndS & ((1 << 255) - 1))
            );
            require(signer != address(0) && handleOf[signer] == 0);
            token.permit(
                signer,
                address(this),
                price,
                deadlineAndToken >> 160,
                uint8(paymentSig.yParityAndS >> 255) + 27,
                paymentSig.r,
                bytes32(paymentSig.yParityAndS & ((1 << 255) - 1))
            );
            token.transferFrom(signer, PROTOCOL_FUND, price);
            handleOf[signer] = handle;
            emit Transfer(address(this), signer, handle);
        }
    }

    /**
     * @param handle           Updates the contents of the KPASS with the given
     *                         IPFS handle.
     */
    function update(uint256 handle) external {
        require(handleOf[msg.sender] != 0);
        handleOf[msg.sender] = handle;
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Revoking related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    event RevokerAssignment(address indexed owner, address indexed revoker, uint256 weight);

    // keccak256("RevokeFriendFor(address friend)");
    bytes32 public constant REVOKE_FRIEND_FOR_TYPEHASH =
        0xfbf2f0fb915c060d6b3043ea7458b132e0cbcd7973bac5644e78e4f17cd28b8e;

    uint256 private constant REVOKES_REMAINING_MASK = uint256(type(uint64).max) << 192;

    mapping(address => mapping(address => uint256)) public revokerWeight;

    // `revokeInfo` layout:
    // |-- revokesRemaining --|--   empty   --|-- lastRevokeTimestamp --|
    // |--        64        --|--    128    --|--          64         --|
    mapping(address => uint256) public revokeInfo;

    function revokesRemaining() external view returns (uint256) {
        return revokeInfo[msg.sender] >> 192;
    }

    /**
     * Returns the timestamp of the most recent revoke event for this account.
     *
     * All KPASSs obtained before this timestamp on this address across all
     * chains are considered invalid.
     *
     * If no revoke event happened, the zero value is returned.
     *
     * @return timestamp of the last revoke event, or zero if none happened.
     */
    function lastRevokeTimestamp(address addr) external view returns (uint64) {
        return uint64(revokeInfo[addr]);
    }

    function _setRevokers(uint256[5] calldata revokers) internal {
        require(revokers[0] & REVOKES_REMAINING_MASK != 0);
        revokeInfo[msg.sender] = (revokeInfo[msg.sender] & type(uint64).max) | (revokers[0] & REVOKES_REMAINING_MASK);

        address rev0Addr = address(uint160(revokers[0]));
        uint256 rev0Weight = (revokers[0] >> 160) & type(uint32).max;
        require(rev0Addr != address(0) && rev0Addr != msg.sender);
        revokerWeight[msg.sender][rev0Addr] = rev0Weight;
        emit RevokerAssignment(msg.sender, rev0Addr, rev0Weight);

        address rev1Addr = address(uint160(revokers[1]));
        require(rev1Addr != address(0) && rev1Addr != msg.sender);
        require(rev1Addr != rev0Addr);
        revokerWeight[msg.sender][rev1Addr] = revokers[1] >> 160;
        emit RevokerAssignment(msg.sender, rev1Addr, revokers[1] >> 160);

        address rev2Addr = address(uint160(revokers[2]));
        require(rev2Addr != address(0) && rev2Addr != msg.sender);
        require(rev2Addr != rev1Addr && rev2Addr != rev0Addr);
        revokerWeight[msg.sender][rev2Addr] = revokers[2] >> 160;
        emit RevokerAssignment(msg.sender, rev2Addr, revokers[2] >> 160);

        address rev3Addr = address(uint160(revokers[3]));
        if (rev3Addr == address(0)) return;
        revokerWeight[msg.sender][rev3Addr] = revokers[3] >> 160;
        emit RevokerAssignment(msg.sender, rev3Addr, revokers[3] >> 160);

        address rev4Addr = address(uint160(revokers[4]));
        if (rev4Addr == address(0)) return;
        revokerWeight[msg.sender][rev4Addr] = revokers[4] >> 160;
        emit RevokerAssignment(msg.sender, rev4Addr, revokers[4] >> 160);
    }

    /**
     * Revokes user's own KPASS, rendering it invalid.
     *
     * The owner may delete their KPASS at any time using this method.
     */
    function revoke() external {
        emit Transfer(msg.sender, address(this), handleOf[msg.sender]);
        revokeInfo[msg.sender] = block.timestamp;
        delete handleOf[msg.sender];
    }

    /**
     * Casts a "social revoke" vote on a friends KPASS.
     *
     * If a friend has granted the user a nonzero "social revoke" weight, the
     * user can invoke this method to cast a "social revoke" vote on their
     * friends KPASS. After calling this method, the users revoke weight is set
     * to zero.
     *
     * @param friend           The wallet address of a friends KPASS.
     */
    function revokeFriend(address friend) external {
        uint256 revInfo = revokeInfo[friend];
        uint256 senderWeight = revokerWeight[friend][msg.sender] << 192;

        require(senderWeight > 0);
        delete revokerWeight[friend][msg.sender];

        unchecked {
            if (senderWeight >= (revInfo & REVOKES_REMAINING_MASK)) {
                revokeInfo[friend] = block.timestamp;
                if (handleOf[friend] != 0) {
                    emit Transfer(friend, address(this), handleOf[friend]);
                    delete handleOf[friend];
                }
            } else {
                revokeInfo[friend] = revInfo - senderWeight;
            }
        }
    }

    /**
     * Casts a social revoke vote for a friend on `signature` creators behalf.
     *
     * This method is particularly useful when the revoker is virtual; the KPASS
     * owner generates a private key and immediately signs a `revokeFriendFor`
     * request and emails the signature to a fiend. This way a friend without an
     * EVM adress (but an email address) can cast a social revoke vote.
     *
     * @param friend           Account whose KPASS will be cast a revoke vote.
     * @param signature        Signature from the revoker, authorizing a revoke
     *                         for `friend`.
     */
    function revokeFriendFor(address friend, Signature calldata signature) external {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(REVOKE_FRIEND_FOR_TYPEHASH, friend)))
        );
        unchecked {
            address revoker = ecrecover(
                digest,
                uint8(signature.yParityAndS >> 255) + 27,
                signature.r,
                bytes32(signature.yParityAndS & ((1 << 255) - 1))
            );
            require(revoker != address(0));
            uint256 revInfo = revokeInfo[friend];
            uint256 revokerW = revokerWeight[friend][revoker] << 192;
            // revokerW > 0 if and only if revokerWeight[friend][revoker] > 0.
            require(revokerW > 0);
            delete revokerWeight[friend][revoker];

            if (revokerW >= (revInfo & REVOKES_REMAINING_MASK)) {
                revokeInfo[friend] = block.timestamp;
                if (handleOf[friend] != 0) {
                    emit Transfer(friend, address(this), handleOf[friend]);
                    delete handleOf[friend];
                }
            } else {
                revokeInfo[friend] = revInfo - revokerW;
            }
        }
    }

    /**
     * Sets the revokers only if the revokesRemaining is zero.
     *
     * @param revokers List of revokers with weight and a threshold.
     */
    function setRevokers(uint256[5] calldata revokers) external {
        require(revokeInfo[msg.sender] & REVOKES_REMAINING_MASK == 0);
        _setRevokers(revokers);
    }

    /**
     * Adds a revoker or increase a revokers weight.
     *
     * @param deltaAndRevoker  Address who is given the revoke vote permission
     *                         and the added weight packed into a single word.
     *                         The first 4 bytes have to be zero, the following
     *                         8 bytes encode the added weight and the last 20
     *                         bytes are the revoker address.
     */
    function addRevoker(uint256 deltaAndRevoker) external {
        address revoker = address(uint160(deltaAndRevoker));
        unchecked {
            uint256 weight = revokerWeight[msg.sender][revoker] + (deltaAndRevoker >> 160);
            // Even after a complete compromise of the wallet private key, the
            // attacker should not be able to decrease revoker weights by
            // overflowing.
            require(weight <= type(uint64).max);
            revokerWeight[msg.sender][revoker] = weight;
            emit RevokerAssignment(msg.sender, revoker, weight);
        }
    }

    /**
     * Reduces a KPASSs revoke threshold by the given amount.
     *
     * @param reduce           The amount to reduce.
     */
    function reduceRevokeThreshold(uint256 reduce) external {
        uint256 threshold = revokeInfo[msg.sender] >> 192;
        require(reduce < threshold);
        unchecked {
            revokeInfo[msg.sender] = (threshold - reduce) << 192;
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Price fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    event PriceChange(address indexed token, uint256 price);

    /**
     * The multiplicative premium for getting a KPASS wihout setting up social
     * revoke. The initial value is 3/2, and adjusted by the KDAO holder vote.
     * thereafter.
     */
    uint256 private revokerlessPremium = (3 << 128) | uint256(2);

    /**
     * The price of creating a KPASS with and without a revoker list denominated
     * in a given token.
     *
     * The first 128 bytes of the returned vaule denotes the price without a
     * revoker list and the last 128 bytes are the discounted price for setting
     * up social revoke.
     *
     * The address 0 is understood as the native token.
     */
    mapping(address => uint256) public priceIn;

    constructor() {
        priceIn[0x0000000000000000000000000000000000000000] = (75e15 << 128) | 50e15;
        priceIn[0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7] = (15e5 << 128) | 10e5;
        priceIn[0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E] = (15e5 << 128) | 10e5;
        priceIn[0x564A341Df6C126f90cf3ECB92120FD7190ACb401] = ((285e5) << 128) | 190e5;
        priceIn[0x9C9e5fD8bbc25984B178FdCE6117Defa39d2db39] = (15e17 << 128) | 10e17;
    }

    /**
     * Updates KPASS prices in a given list of tokens.
     *
     * @param premium          The multiplicative price premium for getting a
     *                         KPASS without specifying a social revokers list.
     *                         The 256-bit value is understood as 128-bit
     *                         numerator followed by 128-bit denominator.
     * @param prices           A list of tuples (price, address) where the
     *                         price is an uint96 and the address is 20 bytes.
     */
    function updatePricesBulk(uint256 premium, uint256[5] calldata prices) external {
        require(msg.sender == VOTING);
        unchecked {
            revokerlessPremium = premium;
            for (uint256 i = 0; i < 5; ++i) {
                if (prices[i] == 0) break;
                address token = address(uint160(prices[i]));
                uint256 price = prices[i] >> 160;
                uint256 t = (price * premium) / uint128(premium);
                priceIn[token] = (t & (type(uint256).max << 128)) | price;
                emit PriceChange(token, price);
            }
        }
    }

    /**
     * Updates the price of a KPASS denominated in a given token.
     *
     * @param priceAndToken    The price as a 96 bit integer, followed by the
     *                         token address for a ERC-20 token or the zero
     *                         address, which is understood as the native
     *                         token.
     */
    function updatePrice(uint256 priceAndToken) external {
        require(msg.sender == VOTING);
        unchecked {
            address token = address(uint160(priceAndToken));
            uint256 price = priceAndToken >> 160;
            uint256 premium = revokerlessPremium;
            uint256 t = (price * premium) / uint128(premium);
            priceIn[token] = (t & (type(uint256).max << 128)) | price;
            emit PriceChange(token, price);
        }
    }
}
