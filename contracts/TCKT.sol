// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./IERC20Permit.sol";
import "./IERC721.sol";
import "./KimlikDAO.sol";

/**
 * @title KimlikDAO TCKT contract.
 */
contract TCKT is IERC721 {
    address private constant NATIVE_TOKEN = address(0);

    event RevokerAssigned(
        address indexed owner,
        address indexed revoker,
        uint256 weight
    );
    /// @notice When a TCKT holder gets their wallet private key exposed
    /// they can either revoke it themselves, or use social revoking.
    /// If they are unable to do either, an exposure report needs to be
    /// filed through a KimlikAŞ authentication.
    event ExposureReported(bytes32 indexed humanID, uint256 timestamp);
    event PriceChanged(address indexed token, uint256 price);
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    mapping(address => uint256) public handles;
    mapping(address => mapping(address => uint256)) public revokerWeight;
    mapping(address => uint256) public revokesRemaining;

    /// @notice The price of a TCKT in a given IERC20Permit token.
    /// The price of a TCKT in the networks native token is represented by
    /// `priceIn[address(0)]`.
    mapping(address => uint256) public priceIn;

    // Maps a HumanID("KimlikDAO:TCKT:exposure") to a reported exposure
    // timestamp.
    mapping(bytes32 => uint256) public exposureReported;

    function name() external pure override returns (string memory) {
        return "TC Kimlik Tokeni";
    }

    function symbol() external pure override returns (string memory) {
        return "TCKT";
    }

    /**
     * @notice Each wallet can hold at most one TCKT at any moment.
     */
    function balanceOf(address addr) external view override returns (uint256) {
        return handles[addr] == 0 ? 0 : 1;
    }

    /**
     * @notice The URI of a given TCKT.
     *
     * Note the tokenID of a TCKT is simply a compact representation of its
     * IPFS handle so we simply prepend the tokenID with "ipfs://Qm".
     */
    function tokenURI(uint256 tokenID)
        external
        pure
        override
        returns (string memory)
    {
        return
            string.concat(
                "ipfs://Qm",
                string(abi.encodePacked(bytes32(tokenID)))
            );
    }

    /**
     * @notice Here we lie about the interfaces we support so that wallets
     * recognize TCKT as an NFT.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
            interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721.
            interfaceId == 0x5b5e139f; // ERC165 interface ID for ERC721Metadata.
    }

    /**
     * @notice To minimize gas fees for TCKT buyers to the maximum extent, we
     * do not forward fees collected in the networks native token to
     * `DAO_KASASI` in each TCKT creation.
     *
     * Instead, the following method gives anyone the right to transfer the
     * entire balance of this contract to `DAO_KASASI` at any time.
     *
     * Further, KimlikDAO does daily sweeps, again using this method and
     * covering the gas fee.
     */
    function sweepNativeToken() external {
        DAO_KASASI.transfer(address(this).balance);
    }

    /**
     * @notice Creates a new TCKT and collects the fee in the native token.
     */
    function create(uint256 handle) public payable {
        require(msg.value >= priceIn[NATIVE_TOKEN]);
        handles[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @notice Creates a new TCKT with the given social revokers and collects
     * the fee in the native token.
     *
     * @param handle           IPFS handle of the persisted TCKT.
     * @param revokeThreshold  The total revoke weight needed before this TCKT
     *                         is destroyed.
     * @param revokers         A list of pairs (weight, address), bit packed
     *                         into a single word, where the weight is a uint96
     *                         and the address is 20 bytes.
     */
    function createWithRevokers(
        uint256 handle,
        uint256 revokeThreshold,
        uint256[] calldata revokers
    ) external payable {
        require(msg.value >= priceIn[NATIVE_TOKEN]);
        handles[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
        revokesRemaining[msg.sender] = revokeThreshold;

        unchecked {
            for (uint256 i = 0; i < revokers.length; ++i) {
                address revoker = address(uint160(revokers[i]));
                revokerWeight[msg.sender][revoker] = revokers[i] >> 160;
                emit RevokerAssigned(msg.sender, revoker, revokers[i] >> 160);
            }
        }
    }

    // TODO(KimlikDAO-bot) We need IERC20Permit support from BiLira to be able
    //                     to accept TRYB.

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
     * @param token            Contract address of a IERC20Permit token.
     * @param handle           IPFS handle of the persisted TCKT.
     * @param deadline         The timestamp until which the payment
     *                         authorization is valid for.
     * @param v                recovery identifier of the signature.
     * @param r                random curve point of the signature.
     * @param s                mapped curve point of the signature.
     */
    function createWithTokenPayment(
        IERC20Permit token,
        uint256 handle,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        uint256 price = priceIn[address(token)];
        require(price > 0);
        token.permit(msg.sender, address(this), price, deadline, v, r, s);
        token.transferFrom(msg.sender, DAO_KASASI, price);
        handles[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @notice Specialization of `createWithTokenPayment()` to USDC.
     *
     * Provides modest gas savings over calling `createWithTokenPayment()`
     * with USDC contract address.
     */
    function createWithUSDCPayment(
        uint256 handle,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        uint256 price = priceIn[address(USDC)];
        USDC.permit(msg.sender, address(this), price, deadline, v, r, s);
        USDC.transferFrom(msg.sender, DAO_KASASI, price);
        handles[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    /**
     * @notice Add a HumanID("KimlikDAO:TCKT:exposure") to exposed list.
     * This can be invoked only by a 2-of-2 threshold signature of
     * KimlikDAO and KimlikAŞ.
     *
     * @param humanID          HumanID("KimlikDAO:TCKT:exposure") of the person
     *                         who reported the private key exposure.
     *
     * TCKT validators are expected to consider all presented TCKTs with
     * the HumanID("KimlikDAO:TCKT:exposure") equaling `humanID` and issuance
     * date earlier than `exposureReported[humanID]` as invalid.
     */
    function reportExposure(bytes32 humanID) external {
        require(msg.sender == THRESHOLD_2OF2_EXPOSURE_LIST_WRITER);
        exposureReported[humanID] = block.timestamp;
        emit ExposureReported(humanID, block.timestamp);
    }

    /**
     * @notice Revokes users own TCKT.
     *
     * The user has the right to delete their own TCKT any time they want using
     * this method.
     */
    function revoke() external {
        emit Transfer(msg.sender, address(this), handles[msg.sender]);
        delete handles[msg.sender];
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
        uint256 remaining = revokesRemaining[friend];
        uint256 senderWeight = revokerWeight[friend][msg.sender];

        require(senderWeight > 0);
        delete revokerWeight[friend][msg.sender];

        unchecked {
            if (senderWeight >= remaining) {
                emit Transfer(friend, address(this), handles[friend]);
                delete handles[friend];
                delete revokesRemaining[friend];
            } else revokesRemaining[friend] = remaining - senderWeight;
        }
    }

    /**
     * @notice Add a revoker or update a revokers weight.
     *
     * A user can adjust their social revoker list and their weight using this
     * method. Note this method does not change the users `revokesRemaining`,
     * which may need to be adjusted separately. If a change to both the
     * revoker list and the revoking threshold is needed, use the
     * `updateRevokerAndThreshold()` method.
     *
     * @param revoker          Address who is given the revoke weight `weight`.
     * @param weight           Weight of the revokers vote.
     */
    function updateRevoker(address revoker, uint256 weight) external {
        revokerWeight[msg.sender][revoker] = weight;
        emit RevokerAssigned(msg.sender, revoker, weight);
    }

    /**
     * @notice Remove a revoker.
     *
     * Note this does not adjust the `remainingRevokers` for the user.
     * Therefore after removing a revoker, social revoking may not work
     * unless the users adjusts the `revokesRemaining`.
     */
    function removeRevoker(address revoker) external {
        delete revokerWeight[msg.sender][revoker];
        emit RevokerAssigned(msg.sender, revoker, 0);
    }

    function setRevokeThreshold(uint256 threshold) external {
        revokesRemaining[msg.sender] = threshold;
    }

    function setRevokerAndThreshold(
        address revoker,
        uint256 weight,
        uint256 threshold
    ) external {
        revokerWeight[msg.sender][revoker] = weight;
        emit RevokerAssigned(msg.sender, revoker, weight);
        revokesRemaining[msg.sender] = threshold;
    }

    /**
     * @notice Updates TCKT prices in a given list of tokens.
     *
     * @param prices           A list of tuples (price, address) where the
     *                         price is an uint96 and the address is 20 bytes.
     *                         Note if the price for a token does not fit in 96
     *                         bits, the `updatePrice()` method should be used
     *                         instead.
     */
    function updatePricesBulk(uint256[] calldata prices) external {
        require(msg.sender == KIMLIKDAO_PRICE_FEEDER);
        unchecked {
            for (uint256 i = 0; i < prices.length; ++i) {
                address token = address(uint160(prices[i]));
                priceIn[token] = prices[i] >> 160;
                emit PriceChanged(token, prices[i] >> 160);
            }
        }
    }

    /**
     * Updates the price of a TCKT denominated in a certain token.
     *
     * @param token            Contract address for a IERC20Permit token or the
     *                         zero address, which is understood as the native
     *                         token.
     * @param price            Price of TCKT denominated in given token.
     */
    function updatePrice(address token, uint256 price) external {
        require(msg.sender == KIMLIKDAO_PRICE_FEEDER);
        priceIn[token] = price;
        emit PriceChanged(token, price);
    }
}
