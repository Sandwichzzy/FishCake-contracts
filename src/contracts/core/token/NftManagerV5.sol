// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../interfaces/IRedemptionPool.sol";
import "../../interfaces/IFishCakeEventManager.sol";
import "../../interfaces/INftManager.sol";
import "../../interfaces/IStakingManager.sol";

/// @custom:oz-upgrades-from NftManagerV4
contract NftManagerV5 is
    INftManager,
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using Strings for uint8;
    using Strings for uint256;

    uint256 public _nextTokenId;
    // don't use 20241016 1630
    string public s_uriPrefix;
    uint256 public s_merchantValue;
    uint256 public s_userValue;

    //30 days = 2592000 s
    uint256 public constant VALID_TIME = 2592000;
    uint256 public constant TOTAL_MINE_AMT = 200_000_000 * 10 ** 6;
    uint256 public constant PRO_MINE_AMT = 1000 * 10 ** 6; //mint pro NFT 返还1000 FCC
    uint256 public constant BASIC_MINE_AMT = 100 * 10 ** 6; //mint basic NFT 返还100 FCC

    IRedemptionPool public s_redemptionPoolAddress;

    uint256 public s_minedAmt;
    IERC20 public s_fccTokenAddr;
    IERC20 public s_tokenUsdtAddr;

    //owner address => deadline timestamp
    mapping(address => uint256) public s_merchantNftDeadline;
    mapping(address => uint256) public s_userNftDeadline;

    //nftTokenID => 1 merchant,2 user ==》 1 pro,2 basic
    mapping(uint256 => uint8) public s_nftMintType;

    string public s_basicNftJson;
    string public s_proNftJson;

    string public _customName;
    string public _customSymbol;

    //Booster NFT 有四类，对应每个月活动收益情况
    string public s_uncommonFishcakeNftJson;
    string public s_rareShrimpNftJson;
    string public s_epicSalmonNftJson;
    string public s_legendaryTunaNftJson;

    IFishCakeEventManager public s_feManagerAddress;

    // tokenId of the active booster NFT for miner
    mapping(address => uint256) public s_minerActiveNft;

    mapping(address => uint256[]) public s_minerHistoryBoosterNft;

    address public s_boosterAddress;

    IStakingManager public s_stakingManagerAddress;

    function __NftManagerStorage_init(address _fccTokenAddr, address _tokenUsdtAddr, address _redemptionPoolAddress)
        internal
        initializer
    {
        s_fccTokenAddr = IERC20(_fccTokenAddr);
        s_tokenUsdtAddr = IERC20(_tokenUsdtAddr);
        s_redemptionPoolAddress = IRedemptionPool(_redemptionPoolAddress);

        _nextTokenId = 1;
        s_merchantValue = 8e7; //购买商家版 pro 价格80USD
        s_userValue = 8e6; //购买用户版NFT basic 价格8USD
        s_minedAmt = 0;

        s_proNftJson = "https://www.fishcake.org/image/1.json";
        s_basicNftJson = "https://www.fishcake.org/image/2.json";
    }

    modifier onlyBooster() {
        require(msg.sender == s_boosterAddress, "NftManagerV5 onlyBooster: Only BoosterAddress can call this function");
        _;
    }

    modifier onlyStakingManager() {
        require(
            msg.sender == address(s_stakingManagerAddress),
            "NftManagerV5 onlyStakingManager: Only StakingManager can call this function"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _fccTokenAddr,
        address _tokenUsdtAddr,
        address _redemptionPoolAddress
    ) public initializer {
        require(_initialOwner != address(0), "NftManager initialize: _initialOwner can't be zero address");
        __ERC721_init("Fishcake Pass NFT", "FNFT");
        __Ownable_init(_initialOwner);
        _transferOwnership(_initialOwner);
        __NftManagerStorage_init(_fccTokenAddr, _tokenUsdtAddr, _redemptionPoolAddress);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function nftUpgradeInit(address _feManagerAddress, address _boosterAddress, address _stakingManagerAddress)
        external
        onlyOwner
    {
        s_uncommonFishcakeNftJson = "https://www.fishcake.org/image/3.json";
        s_rareShrimpNftJson = "https://www.fishcake.org/image/4.json";
        s_epicSalmonNftJson = "https://www.fishcake.org/image/5.json";
        s_legendaryTunaNftJson = "https://www.fishcake.org/image/6.json";
        s_feManagerAddress = IFishCakeEventManager(_feManagerAddress);
        s_stakingManagerAddress = IStakingManager(_stakingManagerAddress);
        s_boosterAddress = _boosterAddress;
    }

    //这个是一次性的NFT，质押完就失效
    function mintBoosterNFT(address miner) external onlyBooster nonReentrant returns (bool, uint256) {
        //根据miner的活动挖矿量来决定铸造哪种类型的Booster NFT
        uint256 decimal = 1e6;
        uint256 mineAmount = s_feManagerAddress.getMinerMineAmount(miner);
        if (mineAmount < 30 * decimal) {
            revert MineAmountNotEnough(mineAmount);
        }
        uint256 boosterTokenId = _nextTokenId++;
        // Booster address call mintBoosterNFT(miner)
        // not msg.sender cuz system records that the miner owns the NFT.
        _safeMint(miner, boosterTokenId);
        if (mineAmount >= 30 * decimal && mineAmount < 90 * decimal) {
            s_nftMintType[boosterTokenId] = 3;
        } else if (mineAmount >= 90 * decimal && mineAmount < 300 * decimal) {
            s_nftMintType[boosterTokenId] = 4;
        } else if (mineAmount >= 300 * decimal && mineAmount < 900 * decimal) {
            s_nftMintType[boosterTokenId] = 5;
        } else {
            s_nftMintType[boosterTokenId] = 6;
        }
        //清空miner的活动挖矿量
        s_feManagerAddress.deleteMinerMineAmount(miner);
        s_minerActiveNft[miner] = boosterTokenId;
        return (true, boosterTokenId);
    }

    //创建NFT，商家版和用户版
    function createNft(
        string memory _businessName,
        string memory _description,
        string memory _imgUrl,
        string memory _businessAddress,
        string memory _website,
        string memory _social,
        uint8 _type
    ) external nonReentrant returns (bool, uint256) {
        require(
            _type == 1 || _type == 2,
            "NftManager createNFT: type can only equal 1 and 2, 1 stand for merchant, 2 stand for personal user"
        );
        uint256 payUsdtAmount = (_type == 1) ? s_merchantValue : s_userValue;
        uint256 nftDeadline = block.timestamp + VALID_TIME;
        if (_type == 1) {
            require(
                s_tokenUsdtAddr.allowance(msg.sender, address(this)) >= s_merchantValue,
                "NftManager createNFT: Merchant allowance must more than 80 U"
            );
            s_merchantNftDeadline[msg.sender] = nftDeadline;
            s_fccTokenAddr.transfer(msg.sender, PRO_MINE_AMT);
        } else {
            require(
                s_tokenUsdtAddr.allowance(msg.sender, address(this)) >= s_userValue,
                "NftManager createNFT: Merchant allowance must more than 8 U"
            );
            s_userNftDeadline[msg.sender] = nftDeadline;
            s_fccTokenAddr.transfer(msg.sender, BASIC_MINE_AMT);
        }
        // 转移USDT到合约
        s_tokenUsdtAddr.transferFrom(msg.sender, address(this), payUsdtAmount);
        // 销售获得的75%USDT转到RedemptionPool合约中
        s_tokenUsdtAddr.transfer(address(s_redemptionPoolAddress), (payUsdtAmount * 75) / 100);
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        s_nftMintType[tokenId] = _type;

        emit CreateNFT(
            msg.sender,
            tokenId,
            _businessName,
            _description,
            _imgUrl,
            _businessAddress,
            _website,
            _social,
            payUsdtAmount,
            nftDeadline,
            _type
        );
        return (true, tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return s_uriPrefix;
    }

    // don't use 20241016 1630
    function setUriPrefix(string memory _uriPrefix) external onlyOwner {
        s_uriPrefix = _uriPrefix;
        emit UriPrefixSet(msg.sender, _uriPrefix);
    }

    function uri(uint256 inputTokenId) public view virtual returns (string memory) {
        return tokenURI(inputTokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "ERC721Metadata: URI query for nonexistent token");
        uint8 nftType = s_nftMintType[tokenId];
        if (nftType == 1) {
            return s_proNftJson;
        } else if (nftType == 2) {
            return s_basicNftJson;
        } else if (nftType == 3) {
            return s_uncommonFishcakeNftJson;
        } else if (nftType == 4) {
            return s_rareShrimpNftJson;
        } else if (nftType == 5) {
            return s_epicSalmonNftJson;
        } else {
            return s_legendaryTunaNftJson;
        }
    }

    function setValues(uint256 _merchantValue, uint256 _userValue) external onlyOwner {
        s_merchantValue = _merchantValue;
        s_userValue = _userValue;
        emit SetValues(msg.sender, _merchantValue, _userValue);
    }

    function withdrawToken(address _tokenAddr, address _account, uint256 _value)
        external
        onlyOwner
        nonReentrant
        returns (bool)
    {
        require(_tokenAddr != address(0x0), "NftManager withdrawToken:token address error.");
        require(IERC20(_tokenAddr).balanceOf(address(this)) >= _value, "NftManager withdrawToken: Balance not enough.");
        IERC20(_tokenAddr).transfer(_account, _value);

        emit WithdrawUToken(msg.sender, _tokenAddr, _account, _value);
        return true;
    }

    function withdrawNativeToken(address payable _recipient, uint256 _amount)
        public
        onlyOwner
        nonReentrant
        returns (bool)
    {
        require(_recipient != address(0x0), "NftManager withdrawNativeToken: recipient address error.");
        require(_amount <= address(this).balance, "NftManager withdrawNativeToken: Balance not enough.");
        (bool _ret,) = _recipient.call{value: _amount}("");
        if (!_ret) {
            revert WithdrawNativeTokenFail(_recipient, _amount);
        }
        emit Withdraw(_recipient, _amount);
        return _ret;
    }

    function getMerchantNTFDeadline(address _account) public view returns (uint256) {
        return s_merchantNftDeadline[_account];
    }

    function getUserNTFDeadline(address _account) public view returns (uint256) {
        return s_userNftDeadline[_account];
    }

    function inActiveMinerBoosterNft(address _miner) external onlyStakingManager {
        s_minerActiveNft[_miner] = 0;
    }

    function getActiveMinerBoosterNft(address _miner) external view returns (uint256) {
        return s_minerActiveNft[_miner];
    }

    function getMinerBoosterNftType(uint256 tokenId) external view returns (uint8) {
        return s_nftMintType[tokenId];
    }

    function getTokenBalance(address tokenAddress) public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function updateNftJson(uint8 _type, string memory _newJsonUrl) external onlyOwner {
        require(_type == 1 || _type == 2, "Invalid NFT type");
        if (_type == 1) {
            s_proNftJson = _newJsonUrl;
        } else {
            s_basicNftJson = _newJsonUrl;
        }
        emit UpdatedNftJson(msg.sender, _type, _newJsonUrl);
    }

    function updateNameAndSymbol(string memory newName, string memory newSymbol) external onlyOwner {
        _customName = newName;
        _customSymbol = newSymbol;
        emit NameSymbolUpdated(newName, newSymbol);
    }

    function name() public view virtual override returns (string memory) {
        return bytes(_customName).length > 0 ? _customName : super.name();
    }

    function symbol() public view virtual override returns (string memory) {
        return bytes(_customSymbol).length > 0 ? _customSymbol : super.symbol();
    }
}
