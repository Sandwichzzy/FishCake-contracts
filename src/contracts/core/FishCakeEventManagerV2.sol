// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IFishCakeEventManager.sol";
import "../interfaces/INftManager.sol";

/// @custom:oz-upgrades-from FishcakeEventManagerV1
contract FishCakeEventManagerV2 is
    Initializable,
    IFishCakeEventManager,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_MINE_AMT = 300_000_000 * 10 ** 6; // Total mining quantity
    uint256 public constant MAX_DEADLINE = 2592000; // 30 days = 2592000 s
    uint256 public constant ONEDAY = 86400; // one day 86400 s
    uint256 public constant MERCHANT_ONCEMAX_MINE_AMT = 240 * 10 ** 6; // pro nft once max mining quantity
    uint256 public constant USER_ONCEMAX_MINE_AMT = 24 * 10 ** 6; // basic nft once max mining quantity

    uint256 public s_minedAmt; // Mined quantity
    uint8 public s_minePercent; // Mining percentage
    bool public s_isMint; // Whether to mint

    IERC20 public s_FccTokenAddr;
    IERC20 public s_UsdtTokenAddr;
    INftManager public s_iNFTManager;

    struct ActivityInfo {
        uint256 activityId; // Activity ID
        address businessAccount; // Initiator's account（0x...）
        string businessName; // Merchant name
        string activityContent; // Activity content
        string latitudeLongitude; // Latitude and longitude
        uint256 activityCreateTime; // Activity creation time
        uint256 activityDeadLine; // Activity end time
        uint8 dropType; // Reward rules: 1 represents average acquisition, 2 represents random.
        uint256 dropNumber; // Number of reward units
        uint256 minDropAmt; // When dropType is 1, fill in 0; when it is 2, fill in the minimum quantity to be received for each unit.
        uint256 maxDropAmt; // When dropType is 1, fill in the quantity of each reward; when it is 2, fill in the maximum quantity to be received for each unit. The total reward quantity is determined by multiplying this field by the number of reward units.
        address tokenContractAddr; //Token Contract Address，For example, USDT contract address: 0x55d398326f99059fF775485246999027B3197955
    }

    struct ActivityInfoExt {
        uint256 activityId; // Activity ID
        uint256 alreadyDropAmts; // Total rewarded quantity
        uint256 alreadyDropNumber; // Total number of rewarded units
        uint256 businessMinedAmt; // Mining rewards obtained by the merchant
        uint256 businessMinedWithdrawedAmt; // Mining rewards already withdrawn by the merchant
        uint8 activityStatus; // Activity status: 1 indicates ongoing, 2 indicates ended
    }

    struct DropInfo {
        uint256 activityId; // Activity ID
        address userAccount; // Initiator's account（0x...）
        uint256 dropTime; // drop Time
        uint256 dropAmt; // drop amount
    }

    uint256[] public s_activityInfoChangedIdx; // Translation: Indices of changed statuses
    ActivityInfo[] public s_activityInfoArrs; // all
    ActivityInfoExt[] public s_activityInfoExtArrs; // Translation: Array of all activities

    DropInfo[] public s_dropInfoArrs; // drop InfoA rrs

    mapping(address => uint256) public s_NTFLastMineTime; // nft last mining time

    mapping(uint256 => mapping(address => bool)) public s_activityDroppedToAccount;

    mapping(address => uint256) public s_minerMineAmount;

    uint256[99] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyNftManager() {
        require(msg.sender == address(s_iNFTManager), "MessageManager: only nft manager can do this operate");
        _;
    }

    function initialize(address _initialOwner, address _fccAddress, address _usdtTokenAddr, address _NFTManagerAddr)
        public
        initializer
    {
        require(_initialOwner != address(0), "FishcakeEventManager initialize: _initialOwner can't be zero address");
        __Ownable_init(_initialOwner);
        _transferOwnership(_initialOwner);
        __ERC20_init("FishCake", "FCC");
        __FishcakeEventManagerStorage_init(_fccAddress, _usdtTokenAddr, _NFTManagerAddr);
    }

    function activityAdd(
        string memory _businessName,
        string memory _activityContent,
        string memory _latitudeLongitude,
        uint256 _activityDeadLine,
        uint256 _totalDropAmts,
        uint8 _dropType,
        uint256 _dropNumber,
        uint256 _minDropAmt,
        uint256 _maxDropAmt,
        address _tokenContractAddr
    ) public nonReentrant returns (bool, uint256) {
        require(_dropType == 2 || _dropType == 1, "FishcakeEventManager activityAdd: Drop Type Error.");
        require(_maxDropAmt >= _minDropAmt, "FishcakeEventManager activityAdd: MaxDropAmt Setup Error.");
        require(_totalDropAmts > 0, "FishcakeEventManager activityAdd: Drop Amount Error.");
        require(
            block.timestamp < _activityDeadLine && _activityDeadLine < block.timestamp + MAX_DEADLINE,
            "FishcakeEventManager activityAdd: Activity DeadLine Error."
        );
        require(
            _totalDropAmts == _maxDropAmt * _dropNumber,
            "FishcakeEventManager activityAdd: Drop Number Not Meet Total Drop Amounts."
        );
        require(
            _totalDropAmts >= 10e5, "FishcakeEventManager activityAdd: Total Drop Amounts Too Little , Minimum of 1."
        );
        require(
            _dropNumber <= 101 || _dropNumber <= _totalDropAmts / 10e6,
            "FishcakeEventManager activityAdd: Drop Number Too Large ,Limit 100 or TotalDropAmts/10."
        );
        require(
            _tokenContractAddr == address(s_UsdtTokenAddr) || _tokenContractAddr == address(s_FccTokenAddr),
            "FishcakeEventManager activityAdd: Token contract address error"
        );
        if (_dropType == 1) {
            _minDropAmt = 0;
        }

        // Transfer token to this contract for locking.
        IERC20(_tokenContractAddr).transferFrom(msg.sender, address(this), _totalDropAmts);

        ActivityInfo memory ai = ActivityInfo({
            activityId: s_activityInfoArrs.length + 1,
            businessAccount: msg.sender,
            businessName: _businessName,
            activityContent: _activityContent,
            latitudeLongitude: _latitudeLongitude,
            activityCreateTime: block.timestamp,
            activityDeadLine: _activityDeadLine,
            dropType: _dropType,
            dropNumber: _dropNumber,
            minDropAmt: _minDropAmt,
            maxDropAmt: _maxDropAmt,
            tokenContractAddr: _tokenContractAddr
        });

        ActivityInfoExt memory aie = ActivityInfoExt({
            activityId: s_activityInfoArrs.length + 1,
            alreadyDropAmts: 0,
            alreadyDropNumber: 0,
            businessMinedAmt: 0,
            businessMinedWithdrawedAmt: 0,
            activityStatus: 1
        });
        s_activityInfoArrs.push(ai);
        s_activityInfoExtArrs.push(aie);
        emit ActivityAdd(
            _msgSender(),
            ai.activityId,
            _totalDropAmts,
            _businessName,
            _activityContent,
            _latitudeLongitude,
            _activityDeadLine,
            _dropType,
            _dropNumber,
            _minDropAmt,
            _maxDropAmt,
            _tokenContractAddr
        );
        return (true, ai.activityId);
    }

    function activityFinish(uint256 _activityId) public nonReentrant returns (bool) {
        require(
            _activityId > 0 && _activityId <= s_activityInfoArrs.length,
            "FishcakeEventManager activityFinish: Activity ID Error."
        );
        ActivityInfoExt storage aie = s_activityInfoExtArrs[_activityId - 1];
        ActivityInfo storage ai = s_activityInfoArrs[_activityId - 1];

        require(ai.businessAccount == msg.sender, "FishcakeEventManager activityFinish: Not The Owner.");
        require(aie.activityStatus == 1, "FishcakeEventManager activityFinish: Activity Already Finished.");

        aie.activityStatus = 2;
        uint256 returnAmount = ai.maxDropAmt * ai.dropNumber - aie.alreadyDropAmts;

        uint256 minedAmount = 0;
        if (returnAmount > 0) {
            IERC20(ai.tokenContractAddr).transfer(msg.sender, returnAmount);
        }

        // ifReward There is only one reward in 24 hours
        if (
            s_isMint && ifReward()
                && (
                    s_iNFTManager.getMerchantNTFDeadline(_msgSender()) > block.timestamp
                        || s_iNFTManager.getUserNTFDeadline(_msgSender()) > block.timestamp
                )
        ) {
            // Get the current percentage of mined tokens
            uint8 currentMinePercent;
            uint256 merchantOnceMaxMineTmpAmt;
            uint256 userOnceMaxMineTmpAmt;
            (currentMinePercent, merchantOnceMaxMineTmpAmt, userOnceMaxMineTmpAmt) = getCurrentMinePercent();
            if (s_minePercent != currentMinePercent) {
                s_minePercent = currentMinePercent;
            }
            if (s_minePercent > 0 && address(s_FccTokenAddr) == ai.tokenContractAddr) {
                uint8 percent = (
                    s_iNFTManager.getMerchantNTFDeadline(_msgSender()) > block.timestamp
                        ? s_minePercent
                        : s_minePercent / 2
                ); //user 打5折

                uint256 maxMineAmtLimit = (
                    s_iNFTManager.getMerchantNTFDeadline(_msgSender()) > block.timestamp
                        ? merchantOnceMaxMineTmpAmt
                        : userOnceMaxMineTmpAmt
                );
                // For each FCC release activity hosted on the platform,
                // the activity initiator can mine tokens based on either 50% of the total token quantity consumed by the activity
                // or 50% of the total number of participants multiplied by 20, whichever is lower.
                uint256 tmpDroppedVal = aie.alreadyDropNumber * 20 * 1e6;
                uint256 tmpBusinessMinedAmt =
                    ((aie.alreadyDropAmts > tmpDroppedVal ? tmpDroppedVal : aie.alreadyDropAmts) * percent) / 100;
                if (tmpBusinessMinedAmt > maxMineAmtLimit) {
                    tmpBusinessMinedAmt = maxMineAmtLimit;
                }
                if (TOTAL_MINE_AMT > s_minedAmt) {
                    if (TOTAL_MINE_AMT > s_minedAmt + tmpBusinessMinedAmt) {
                        aie.businessMinedAmt = tmpBusinessMinedAmt;
                        s_minedAmt += tmpBusinessMinedAmt;
                        s_FccTokenAddr.transfer(msg.sender, tmpBusinessMinedAmt);
                        s_minerMineAmount[msg.sender] += tmpBusinessMinedAmt;
                        minedAmount = tmpBusinessMinedAmt;
                    } else {
                        aie.businessMinedAmt = TOTAL_MINE_AMT - s_minedAmt;
                        s_minedAmt += aie.businessMinedAmt;
                        s_FccTokenAddr.transfer(msg.sender, aie.businessMinedAmt);
                        s_minerMineAmount[msg.sender] += aie.businessMinedAmt;
                        minedAmount = aie.businessMinedAmt;
                        s_isMint = false;
                    }
                    s_NTFLastMineTime[msg.sender] = block.timestamp;
                }
            }
        }
        s_activityInfoChangedIdx.push(_activityId - 1);

        emit ActivityFinish(_activityId, ai.tokenContractAddr, returnAmount, minedAmount);
        return true;
    }

    function drop(uint256 _activityId, address _userAccount, uint256 _dropAmt) external nonReentrant returns (bool) {
        require(
            s_activityDroppedToAccount[_activityId][_userAccount] == false,
            "FishcakeEventManager drop: User Has Dropped."
        );
        ActivityInfo storage ai = s_activityInfoArrs[_activityId - 1];
        ActivityInfoExt storage aie = s_activityInfoExtArrs[_activityId - 1];

        require(aie.activityStatus == 1, "FishcakeEventManager drop: Activity Status Error.");
        require(ai.businessAccount == msg.sender, "FishcakeEventManager drop: Not The Owner.");
        require(ai.activityDeadLine >= block.timestamp, "FishcakeEventManager drop: Activity Has Expired.");

        if (ai.dropType == 2) {
            require(
                _dropAmt <= ai.maxDropAmt && _dropAmt >= ai.minDropAmt, "FishcakeEventManager drop: Drop Amount Error."
            );
        } else {
            _dropAmt = ai.maxDropAmt;
        }

        require(ai.dropNumber > aie.alreadyDropNumber, "FishcakeEventManager drop: Exceeded the number of rewards.");
        require(
            ai.maxDropAmt * ai.dropNumber >= _dropAmt + aie.alreadyDropAmts,
            "FishcakeEventManager drop: The reward amount has been exceeded."
        );

        IERC20(ai.tokenContractAddr).transfer(_userAccount, _dropAmt);
        s_activityDroppedToAccount[_activityId][_userAccount] = true;

        DropInfo memory di =
            DropInfo({activityId: _activityId, userAccount: _userAccount, dropTime: block.timestamp, dropAmt: _dropAmt});
        s_dropInfoArrs.push(di);
        aie.alreadyDropAmts += _dropAmt;
        aie.alreadyDropNumber++;

        emit Drop(_userAccount, _activityId, _dropAmt);
        return true;
    }

    function getMinerMineAmount(address _miner) external view returns (uint256) {
        return s_minerMineAmount[_miner];
    }

    function deleteMinerMineAmount(address _miner) external onlyNftManager {
        delete s_minerMineAmount[_miner];
    }

    // ======================= internal =======================
    function __FishcakeEventManagerStorage_init(address _fccAddress, address _usdtTokenAddr, address _NFTManagerAddr)
        internal
        initializer
    {
        s_FccTokenAddr = IERC20(_fccAddress);
        s_UsdtTokenAddr = IERC20(_usdtTokenAddr);
        s_iNFTManager = INftManager(_NFTManagerAddr);

        s_minedAmt = 0;
        s_minePercent = 50;
        s_isMint = true;
    }

    function getCurrentMinePercent() internal view returns (uint8, uint256, uint256) {
        uint8 currentMinePercent = 0;
        uint256 merchantOnceMaxMineTmpAmt = 0;
        uint256 userOnceMaxMineTmpAmt = 0;
        if (s_minedAmt < 30_000_000 * 1e6) {
            currentMinePercent = 50;
            merchantOnceMaxMineTmpAmt = 60 * 10 ** 6;
            userOnceMaxMineTmpAmt = 6 * 10 ** 6;
        } else if (s_minedAmt < 100_000_000 * 1e6) {
            currentMinePercent = 40;
            merchantOnceMaxMineTmpAmt = 30 * 10 ** 6;
            userOnceMaxMineTmpAmt = 3 * 10 ** 6;
        } else if (s_minedAmt < 200_000_000 * 1e6) {
            currentMinePercent = 20;
            merchantOnceMaxMineTmpAmt = 15 * 10 ** 6;
            userOnceMaxMineTmpAmt = 2 * 10 ** 6;
        } else if (s_minedAmt < 300_000_000 * 1e6) {
            currentMinePercent = 10;
            merchantOnceMaxMineTmpAmt = 8 * 10 ** 6;
            userOnceMaxMineTmpAmt = 1 * 10 ** 6;
        } else {
            currentMinePercent = 0;
            merchantOnceMaxMineTmpAmt = 0;
            userOnceMaxMineTmpAmt = 0;
        }
        return (currentMinePercent, merchantOnceMaxMineTmpAmt, userOnceMaxMineTmpAmt);
    }

    function ifReward() internal view returns (bool _ret) {
        if (s_NTFLastMineTime[_msgSender()] == 0) {
            _ret = true;
        } else if (block.timestamp - s_NTFLastMineTime[_msgSender()] >= ONEDAY) {
            _ret = true;
        } else {
            _ret = false;
        }
    }
}
