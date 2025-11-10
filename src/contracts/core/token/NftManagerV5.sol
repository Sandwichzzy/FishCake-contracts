// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../../interfaces/IRedemptionPool.sol";
import "../../interfaces/IFishcakeEventManager.sol";
import "../../interfaces/INftManager.sol";
import "../../interfaces/IStakingManager.sol";

contract NftManagerV5 is Initializable, INftManager {
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
    uint256 public constant PRO_MINE_AMT = 1000 * 10 ** 6;
    uint256 public constant BASIC_MINE_AMT = 100 * 10 ** 6;

    IRedemptionPool public s_redemptionPoolAddress;

    uint256 public s_minedAmt;
    IERC20 public s_fccTokenAddr;
    IERC20 public s_tokenUsdtAddr;

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

    IFishcakeEventManager public s_feManagerAddress;

    mapping(address => uint256) public s_minerActiveNft;

    mapping(address => uint256[]) public s_minerHistoryBoosterNft;

    address public s_boosterAddress;

    IStakingManager public s_stakingManagerAddress;

    function __NftManagerStorage_init(address _fccTokenAddr, address _tokenUsdtAddr, address _redemptionPoolAddress)
        internal
        initializer
    {
        fccTokenAddr = IERC20(_fccTokenAddr);
        tokenUsdtAddr = IERC20(_tokenUsdtAddr);
        redemptionPoolAddress = IRedemptionPool(_redemptionPoolAddress);

        _nextTokenId = 1;
        merchantValue = 8e7;
        userValue = 8e6;
        minedAmt = 0;

        proNftJson = "https://www.fishcake.org/image/1.json";
        basicNftJson = "https://www.fishcake.org/image/2.json";
    }
}
