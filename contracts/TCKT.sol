// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./IERC20Permit.sol";
import "./IERC721.sol";
import "./KimlikDAO.sol";

contract TCKT is IERC721 {
    IERC20Permit constant USDC =
        IERC20Permit(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);

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
    // timestamp
    mapping(bytes32 => uint256) public exposureReported;

    function name() external pure override returns (string memory) {
        return "TC Kimlik Tokeni";
    }

    function symbol() external pure override returns (string memory) {
        return "TCKT";
    }

    function tokenURI(uint256 handle)
        external
        pure
        override
        returns (string memory)
    {
        return
            string.concat(
                "ipfs://Qm",
                string(abi.encodePacked(bytes32(handle)))
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
     * do not forward fees collected in networks native token to `DAO_KASASI`
     * in each TCKT creation.
     *
     * Instead, the following method gives any one the right to transfer the
     * entire balance of this contract to `DAO_KASASI` at any time.
     *
     * Further, KimlikDAO does daily sweeps, again using this method and
     * covering the gas fee.
     */
    function sweepNativeToken() external {
        DAO_KASASI.transfer(address(this).balance);
    }

    function create(uint256 handle) public payable {
        require(msg.value >= priceIn[address(0)]);
        handles[msg.sender] = handle;
        emit Transfer(address(this), msg.sender, handle);
    }

    function createWithRevokers(
        uint256 handle,
        uint256 revokeThreshold,
        uint256[] calldata revokers
    ) external payable {
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

    // TODO(KimlikDAO-bot) We need IERC20Permit support from BiLira to be able to accept TRYB.

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
     * @param humanID    HumanID("KimlikDAO:TCKT:exposure") of the person who
     *                   reported the private key exposure.
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

    function revoke() external {
        emit Transfer(msg.sender, address(this), handles[msg.sender]);
        delete handles[msg.sender];
    }

    function revokeOther(address other) external {
        uint256 remaining = revokesRemaining[other];
        uint256 senderWeight = revokerWeight[other][msg.sender];

        require(senderWeight > 0);
        delete revokerWeight[other][msg.sender];

        unchecked {
            if (senderWeight >= remaining) {
                emit Transfer(other, address(this), handles[other]);
                delete handles[other];
                delete revokesRemaining[other];
            } else revokesRemaining[other] = remaining - senderWeight;
        }
    }

    function setRevoker(address revoker, uint256 weight) external {
        revokerWeight[msg.sender][revoker] = weight;
        emit RevokerAssigned(msg.sender, revoker, weight);
    }

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

    function updatePrice(address token, uint256 price) external {
        require(msg.sender == KIMLIKDAO_PRICE_FEEDER);
        priceIn[token] = price;
        emit PriceChanged(token, price);
    }
}
