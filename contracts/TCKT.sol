// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DAO_KASASI, OYLAMA, TCKT_SIGNERS} from "interfaces/Addresses.sol";
import {IDIDSigners} from "./IDIDSigners.sol";
import {IERC20, IERC20Permit} from "interfaces/IERC20Permit.sol";
import {IERC721} from "interfaces/IERC721.sol";

/**
 * @title KimlikDAO TCKT contract.
 * @author KimlikDAO
 */
contract TCKT is IERC721 {
    mapping(uint256 => uint256) public handleOf;

    function name() external pure override returns (string memory) {
        return "KimlikDAO TC Kimlik Tokeni";
    }

    function symbol() external pure override returns (string memory) {
        return "TCKT";
    }

    /**
     * @notice Returns the number of TCKTs in a given account, which is 0 or 1.
     *
     * Each wallet can hold at most one TCKT, however a new TCKT can be minted
     * to the same address at any time replacing the previous one, say after
     * a personal information change occurs.
     */
    function balanceOf(address addr) external view override returns (uint256) {
        return handleOf[uint160(addr)] == 0 ? 0 : 1;
    }

    /**
     * @notice The URI of a given TCKT.
     *
     * Note the tokenID of a TCKT is simply a compact representation of its
     * IPFS handle so we simply base58 encode the array [0x12, 0x20, tokenID].
     */
    function tokenURI(uint256 id)
        external
        pure
        override
        returns (string memory)
    {
        unchecked {
            bytes memory toChar = bytes(
                "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
            );
            uint256 magic = 0x4e5a461f976ce5b9229582822e96e6269e5d6f18a5960a04480c6825748ba04;
            bytes
                memory out = "https://ipfs.kimlikdao.org/ipfs/Qm____________________________________________";
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
     * @notice Here we claim to support the full ERC721 interface so that
     * wallets recognize TCKT as an NFT, even though TCKTs transfer methods are
     * disabled.
     */
    function supportsInterface(bytes4 interfaceId)
        external
        pure
        override
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
            interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721.
            interfaceId == 0x5b5e139f; // ERC165 interface ID for ERC721Metadata.
    }

    /**
     * @notice Creates a new TCKT and collects the fee in the native token.
     */
    function create(uint256 handle) external payable {
        require(msg.value >= (priceIn[address(0)] >> 128));
        handleOf[uint160(msg.sender)] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @notice To minimize gas fees for TCKT buyers to the maximum extent, we
     * do not forward fees collected in the networks native token to
     * `DAO_KASASI` in each TCKT creation.
     *
     * Instead, the following method gives anyone the right to transfer the
     * entire native token balance of this contract to `DAO_KASASI` at any
     * time.
     *
     * Further, KimlikDAO does weekly sweeps, again using this method and
     * covering the gas fee.
     */
    function sweepNativeToken() external {
        DAO_KASASI.transfer(address(this).balance);
    }

    /**
     * Moves ERC20 tokens sent to this address by accident to `DAO_KASASI`.
     */
    function sweepToken(IERC20 token) external {
        token.transfer(DAO_KASASI, token.balanceOf(address(this)));
    }

    /**
     * @notice Creates a new TCKT with the given social revokers and collects
     * the fee in the native token.
     *
     * @param handle           IPFS handle of the persisted TCKT.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes. Further, the first
     *                         word contains the revokeThreshold in the
     *                         leftmost 64 bits.
     */
    function createWithRevokers(uint256 handle, uint256[5] calldata revokers)
        external
        payable
    {
        require(msg.value >= uint128(priceIn[address(0)]));
        handleOf[uint160(msg.sender)] = handle;
        emit Transfer(address(this), msg.sender, handle);
        setRevokers(revokers);
    }

    /**
     * @param handle           IPFS handle of the persisted TCKT.
     * @param token            Contract address of a IERC20 token.
     */
    function createWithTokenPayment(uint256 handle, IERC20 token) external {
        uint256 price = priceIn[address(token)] >> 128;
        require(price > 0);
        token.transferFrom(msg.sender, DAO_KASASI, price);
        handleOf[uint160(msg.sender)] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @notice Creates a TCKT and collects the fee in the provided `token`.
     *
     * The provided token has to be IERC20Permit, in particular, it needs to
     * support approval by signature.
     *
     * Note if a price change occurs between the moment the user signs off the
     * payment and this method is called, the method call will fail as the
     * signature will be invalid. However, the price changes happen at most
     * once a week and off peak hours by an autonomous vote of TCKO holders.
     *
     * @param handle           IPFS handle of the persisted TCKT.
     * @param deadlineAndToken Contract address of a IERC20Permit token and
     *                         the timestamp until which the payment
     *                         authorization is valid for.
     * @param r                ECDSA r value of the token spend permit.
     * @param yParityAndS      ECSSA s and v values combined.
     */
    function createWithTokenPermit(
        uint256 handle,
        uint256 deadlineAndToken,
        bytes32 r,
        uint256 yParityAndS
    ) external {
        IERC20Permit token = IERC20Permit(address(uint160(deadlineAndToken)));
        uint256 price = priceIn[address(token)] >> 128;
        require(price > 0);
        unchecked {
            token.permit(
                msg.sender,
                address(this),
                price,
                deadlineAndToken >> 160,
                uint8(yParityAndS >> 255) + 27,
                r,
                bytes32(yParityAndS & ((1 << 255) - 1))
            );
        }
        token.transferFrom(msg.sender, DAO_KASASI, price);
        handleOf[uint160(msg.sender)] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @param handle           IPFS handle of the persisted TCKT.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes.
     * @param token            Contract address of a IERC20Permit token.
     */
    function createWithRevokersWithTokenPayment(
        uint256 handle,
        uint256[5] calldata revokers,
        IERC20 token
    ) external {
        uint256 price = uint128(priceIn[address(token)]);
        require(price > 0);
        token.transferFrom(msg.sender, DAO_KASASI, price);
        handleOf[uint160(msg.sender)] = handle;
        emit Transfer(address(this), msg.sender, handle);
        setRevokers(revokers);
    }

    /**
     * @param handle           IPFS handle of the persisted TCKT.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes.
     * @param deadlineAndToken Contract address of a IERC20Permit token.
     * @param r                ECDSA r value of the token spend permit.
     * @param yParityAndS      ECSSA s and v values combined.
     */
    function createWithRevokersWithTokenPermit(
        uint256 handle,
        uint256[5] calldata revokers,
        uint256 deadlineAndToken,
        bytes32 r,
        uint256 yParityAndS
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
                uint8(yParityAndS >> 255) + 27,
                r,
                bytes32(yParityAndS & ((1 << 255) - 1))
            );
        }
        token.transferFrom(msg.sender, DAO_KASASI, price);
        handleOf[uint160(msg.sender)] = handle;
        emit Transfer(address(this), msg.sender, handle);
        setRevokers(revokers);
    }

    // keccak256(
    //     abi.encode(
    //         keccak256(
    //             "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    //         ),
    //         keccak256(bytes("TCKT")),
    //         keccak256(bytes("1")),
    //         43114,
    //         address(this)
    //     )
    // );
    bytes32 public constant DOMAIN_SEPARATOR =
        0x7f09fc8776645c556371127677a2206a00976e7f49fa8690739ee07c5b3bc805;

    // keccak256("CreateFor(uint256 handle)")
    bytes32 public constant CREATE_FOR_TYPEHASH =
        0xe0b70ef26ac646b5fe42b7831a9d039e8afa04a2698e03b3321e5ca3516efe70;

    /**
     * Creates a TCKT on users behalf, covering the tx fee.
     *
     * The user has to explicitly authorize the TCKT creation with the
     * (createR, createSS) signature and the token payment with the
     * (paymentR, paymentSS) signature.
     *
     * The gas fee is paid by the transaction sender, which typically is
     * someone other than the TCKT owner. This enables gasless TCKT mints,
     * wherein the gas fee is covered by the KimlikDAO gas station.
     *
     * @param handle           IPFS handle with which to create the TCKT.
     * @param createR          ECDSA r value of the create signature.
     * @param createSS         ECDSA s and v values combined.
     * @param deadlineAndToken The payment token and the deadline for the token
     *                         permit signature.
     * @param paymentR         ECDSA r value of the token spend permit signature.
     * @param paymentSS        ECDSA s and v values combined.
     */
    function createFor(
        uint256 handle,
        bytes32 createR,
        uint256 createSS,
        uint256 deadlineAndToken,
        bytes32 paymentR,
        uint256 paymentSS
    ) external {
        IERC20Permit token = IERC20Permit(address(uint160(deadlineAndToken)));
        uint256 price = priceIn[address(token)] >> 128;
        require(price > 0);
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(CREATE_FOR_TYPEHASH, handle))
                )
            );
            address signer = ecrecover(
                digest,
                uint8(createSS >> 255) + 27,
                createR,
                bytes32(createSS & ((1 << 255) - 1))
            );
            require(signer != address(0) && handleOf[uint160(signer)] == 0);
            token.permit(
                signer,
                address(this),
                price,
                deadlineAndToken >> 160,
                uint8(paymentSS >> 255) + 27,
                paymentR,
                bytes32(paymentSS & ((1 << 255) - 1))
            );
            token.transferFrom(signer, DAO_KASASI, price);
            handleOf[uint160(signer)] = handle;
            emit Transfer(address(this), signer, handle);
        }
    }

    /**
     * @param handle           Updates the contents of the TCKT with the given
     *                         IFPS handle.
     */
    function update(uint256 handle) external {
        require(handleOf[uint160(msg.sender)] != 0);
        handleOf[uint160(msg.sender)] = handle;
    }

    /**
     * Appends a document to a TCKT.
     *
     * @param docHandle        IPFS hash of the persisted document.
     */
    function addDocument(uint256 docHandle) external {
        uint256 handle = handleOf[uint160(msg.sender)];
        require(handle != 0);
        uint256 prevDoc = handleOf[handle];
        handleOf[handle] = docHandle;
        if (prevDoc != 0 && handleOf[docHandle] == 0)
            handleOf[docHandle] = prevDoc;
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Revoking related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    event RevokerAssignment(
        address indexed owner,
        address indexed revoker,
        uint256 weight
    );

    // keccak256("RevokeFriendFor(address friend)");
    bytes32 public constant REVOKE_FRIEND_FOR_TYPEHASH =
        0xfbf2f0fb915c060d6b3043ea7458b132e0cbcd7973bac5644e78e4f17cd28b8e;

    uint256 private constant REVOKES_REMAINING_MASK =
        uint256(type(uint64).max) << 192;

    mapping(address => mapping(address => uint256)) public revokerWeight;

    // `revokeInfo` layout:
    // |-- revokesRemaining --|--   empty   --|-- lastRevokeTimestamp --|
    // |--        64        --|--    128    --|--          64         --|
    mapping(address => uint256) public revokeInfo;

    function revokesRemaining() external view returns (uint256) {
        return revokeInfo[msg.sender] >> 192;
    }

    function lastRevokeTimestamp(address addr) external view returns (uint64) {
        return uint64(revokeInfo[addr]);
    }

    function setRevokers(uint256[5] calldata revokers) internal {
        revokeInfo[msg.sender] =
            (revokeInfo[msg.sender] & type(uint64).max) |
            (revokers[0] & REVOKES_REMAINING_MASK);

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
        revokerWeight[msg.sender][rev4Addr] = revokers[4] << 160;
        emit RevokerAssignment(msg.sender, rev4Addr, revokers[4] >> 160);
    }

    /**
     * @notice Revokes users own TCKT.
     *
     * The user has the right to delete their own TCKT at any time using this
     * method.
     */
    function revoke() external {
        emit Transfer(msg.sender, address(this), handleOf[uint160(msg.sender)]);
        revokeInfo[msg.sender] = block.timestamp;
        delete handleOf[uint160(msg.sender)];
    }

    /**
     * @notice Cast a "social revoke" vote to a friends TCKT.
     *
     * If a friend gave the user a nonzero social revoke weight, the user can
     * use this method to vote "social revoke" of their friends TCKT. After
     * calling this method, the users revoke weight is zeroed.
     *
     * @param friend           The wallet address of a friends TCKT.
     */
    function revokeFriend(address friend) external {
        uint256 revInfo = revokeInfo[friend];
        uint256 senderWeight = revokerWeight[friend][msg.sender] << 192;

        require(senderWeight > 0);
        delete revokerWeight[friend][msg.sender];

        unchecked {
            if (senderWeight >= (revInfo & REVOKES_REMAINING_MASK)) {
                revokeInfo[friend] = block.timestamp;
                if (handleOf[uint160(friend)] != 0) {
                    emit Transfer(
                        friend,
                        address(this),
                        handleOf[uint160(friend)]
                    );
                    delete handleOf[uint160(friend)];
                }
            } else revokeInfo[friend] = revInfo - senderWeight;
        }
    }

    /**
     * Cast a social revoke vote by signature.
     *
     * This method is particulatly useful when the revoker is virtual; the TCKT
     * owner generates a private key and immediately signs a `revokeFriendFor`
     * request and e-mails the signature to a fiend. This way a friend who
     * doesn't have an EVM adress (but an email address) can cast a social
     * revoke vote.
     *
     * @param r                ECDSA r value for revokeFriendFor signature.
     * @param yParityAndS      ECDSA s and v values combined.
     */
    function revokeFriendFor(
        address friend,
        bytes32 r,
        uint256 yParityAndS
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(REVOKE_FRIEND_FOR_TYPEHASH, friend))
            )
        );
        unchecked {
            address revoker = ecrecover(
                digest,
                uint8(yParityAndS >> 255) + 27,
                r,
                bytes32(yParityAndS & ((1 << 255) - 1))
            );
            require(revoker != address(0));
            uint256 revInfo = revokeInfo[friend];
            uint256 revokerW = revokerWeight[friend][revoker] << 192;
            require(revokerW > 0);
            delete revokerWeight[friend][revoker];

            if (revokerW >= (revInfo & REVOKES_REMAINING_MASK)) {
                revokeInfo[friend] = block.timestamp;
                if (handleOf[uint160(friend)] != 0) {
                    emit Transfer(
                        friend,
                        address(this),
                        handleOf[uint160(friend)]
                    );
                    delete handleOf[uint160(friend)];
                }
            } else revokeInfo[friend] = revInfo - revokerW;
        }
    }

    /**
     * @notice Add a revoker or increase a revokers weight.
     *
     * @param deltaAndRevoker  Address who is given the revoke vote permission.
     */
    function addRevoker(uint256 deltaAndRevoker) external {
        address revoker = address(uint160(deltaAndRevoker));
        uint256 weight = revokerWeight[msg.sender][revoker] +
            (deltaAndRevoker >> 160);
        revokerWeight[msg.sender][revoker] = weight;
        emit RevokerAssignment(msg.sender, revoker, weight);
    }

    /**
     * @notice Reduce revoker threshold by given amount.
     *
     * @param reduce           The amount to reduce.
     */
    function reduceRevokeThreshold(uint256 reduce) external {
        uint256 threshold = revokeInfo[msg.sender] >> 192;
        revokeInfo[msg.sender] = (threshold - reduce) << 192; // Checked substraction
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Price fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    event PriceChange(address indexed token, uint256 price);

    /// The multiplicative premium for getting a TCKT wihout setting up social
    /// revoke. The initial value is 3/2, and adjusted by DAO vote.
    uint256 private revokerlessPremium = (3 << 128) | uint256(2);

    mapping(address => uint256) public priceIn;

    /**
     * @notice Updates TCKT prices in a given list of tokens.
     *
     * @param premium          The multiplicative price premium for getting a
     *                         TCKT without specifying a social revokers list.
     *                         The 256-bit value is understood as 128-bit
     *                         numerator followed by 128-bit denominator.
     * @param prices           A list of tuples (price, address) where the
     *                         price is an uint96 and the address is 20 bytes.
     *                         Note if the price for a token does not fit in 96
     *                         bits, the `updatePrice()` method should be used
     *                         instead.
     */
    function updatePricesBulk(uint256 premium, uint256[5] calldata prices)
        external
    {
        require(msg.sender == OYLAMA);
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
     * Updates the price of a TCKT denominated in a certain token.
     *
     * @param priceAndToken    The price as a 96 bit integer, followed by the
     *                         token address for a IERC20 token or the zero
     *                         address, which is understood as the native
     *                         token.
     */
    function updatePrice(uint256 priceAndToken) external {
        require(msg.sender == OYLAMA);
        unchecked {
            address token = address(uint160(priceAndToken));
            uint256 price = priceAndToken >> 160;
            uint256 premium = revokerlessPremium;
            uint256 t = (price * premium) / uint128(premium);
            priceIn[token] = (t & (type(uint256).max << 128)) | price;
            emit PriceChange(token, price);
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //
    // Exposure report related fields and methods
    //
    ///////////////////////////////////////////////////////////////////////////

    /// @notice When a TCKT holder gets their wallet private key exposed
    /// they can either revoke their TCKT themselves, or use social revoking.
    ///
    /// If they are unable to do either, they need to obtain a new TCKT (to a
    /// new address), with which they can file an exposure report via the
    /// `reportExposure()` method. Doing so invalidates all TCKTs they have
    /// obtained before the timestamp of their most recent TCKT.
    event ExposureReport(bytes32 indexed exposureReportID, uint64 timestamp);

    /// Maps a `exposureReportID` to a reported exposure timestamp,
    /// or zero if no exposure has been reported.
    mapping(bytes32 => uint256) public exposureReported;

    /**
     * @notice Add a `exposureReportID` to exposed list.
     * A nonce is not needed since the `exposureReported[exposureReportID]`
     * value can only be incremented.
     *
     * @param exposureReportID of the person whose wallet keys were exposed.
     * @param timestamp        of the exposureReportID signatures.
     * @param r                ECDSA r value of the validator signatures.
     * @param yParityAndS      ECSSA s and v values combined.
     */
    function reportExposure(
        bytes32 exposureReportID,
        uint64 timestamp,
        bytes32[3] calldata r,
        uint256[3] calldata yParityAndS
    ) external {
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(exposureReportID, timestamp)
            );
            address[3] memory signer;
            for (uint256 i = 0; i < 3; ++i) {
                signer[i] = ecrecover(
                    digest,
                    uint8(yParityAndS[i] >> 255) + 27,
                    r[i],
                    bytes32(yParityAndS[i] & ((1 << 255) - 1))
                );
                uint256 info = IDIDSigners(TCKT_SIGNERS).signerInfo(signer[i]);
                uint256 endTs = uint64(info >> 128);
                require(
                    info != 0 &&
                        uint64(info) <= timestamp &&
                        (endTs == 0 || timestamp < endTs)
                );
            }
            require(
                signer[0] != signer[1] &&
                    signer[0] != signer[2] &&
                    signer[1] != signer[2]
            );
        }
        // Exposure report timestamp can only be incremented.
        require(exposureReported[exposureReportID] < timestamp);
        exposureReported[exposureReportID] = timestamp;
        emit ExposureReport(exposureReportID, timestamp);
    }
}
