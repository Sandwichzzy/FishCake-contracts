// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IFishCakeEventManager.sol";
import "../interfaces/INftManager.sol";

/**
 * @title FishCakeEventManager
 * @notice Manages airdrop activities and mining rewards for the FishCake ecosystem
 * @dev This contract allows merchants to create token distribution activities and earn mining rewards based on participation
 */
contract FishCakeEventManager is
    Initializable,
    IFishCakeEventManager,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @notice Total amount of FCC tokens available for mining rewards (300 million)
    uint256 public constant TOTAL_MINE_AMT = 300_000_000 * 10 ** 6;

    /// @notice Maximum duration for activities (30 days in seconds)
    uint256 public constant MAX_DEADLINE = 2592000;

    /// @notice Duration of one day in seconds
    uint256 public constant ONEDAY = 86400;

    /// @notice Total amount of tokens that have been mined
    uint256 public s_minedAmt;

    /// @notice Current mining reward percentage (decreases as more tokens are mined)
    uint8 public s_minePercent;

    /// @notice Flag indicating whether mining is still active
    bool public s_isMint;

    /// @notice FCC token contract address
    IERC20 public s_FccTokenAddr;

    /// @notice USDT token contract address
    IERC20 public s_UsdtTokenAddr;

    /// @notice NFT Manager contract interface
    INftManager public s_iNFTManager;

    /**
     * @notice Stores basic information about an airdrop activity
     * @dev All token amounts are in the token's smallest unit (considering decimals)
     */
    struct ActivityInfo {
        uint256 activityId; // Unique identifier for the activity
        address businessAccount; // Address of the merchant who created the activity
        string businessName; // Display name of the merchant
        string activityContent; // Description or title of the activity
        string latitudeLongitude; // Geographic coordinates for the activity location
        uint256 activityCreateTime; // Timestamp when activity was created
        uint256 activityDeadLine; // Timestamp when activity expires
        uint8 dropType; // Distribution type: 1 = equal distribution, 2 = random amount
        uint256 dropNumber; // Total number of reward units available
        uint256 minDropAmt; // Minimum amount per drop (0 for dropType 1, used for dropType 2)
        uint256 maxDropAmt; // Maximum amount per drop (fixed amount for type 1, upper limit for type 2)
        address tokenContractAddr; // Address of the token being distributed (FCC or USDT)
    }

    /**
     * @notice Stores extended information tracking activity progress and rewards
     */
    struct ActivityInfoExt {
        uint256 activityId; // Activity identifier (matches ActivityInfo.activityId)
        uint256 alreadyDropAmts; // Total amount of tokens already distributed
        uint256 alreadyDropNumber; // Number of drops already claimed
        uint256 businessMinedAmt; // FCC mining rewards earned by the merchant
        uint256 businessMinedWithdrawedAmt; // Mining rewards already withdrawn (currently unused)
        uint8 activityStatus; // Current status: 1 = active, 2 = finished
    }

    /**
     * @notice Records individual token drop transactions
     */
    struct DropInfo {
        uint256 activityId; // ID of the activity this drop belongs to
        address userAccount; // Address of the user who received the drop
        uint256 dropTime; // Timestamp when the drop occurred
        uint256 dropAmt; // Amount of tokens dropped to the user
    }

    /// @notice Array of activity indices that have been modified (for tracking status changes)
    uint256[] public s_activityInfoChangedIdx;

    /// @notice Array storing all activity basic information
    ActivityInfo[] public s_activityInfoArrs;

    /// @notice Array storing all activity extended information
    ActivityInfoExt[] public s_activityInfoExtArrs;

    /// @notice Array storing all drop transaction records
    DropInfo[] public s_dropInfoArrs;

    /// @notice Tracks the last time each address earned mining rewards (for 24-hour cooldown)
    mapping(address => uint256) public s_NTFLastMineTime;

    /// @notice Tracks whether a user has already received a drop from a specific activity
    mapping(uint256 => mapping(address => bool)) public s_activityDroppedToAccount;

    /// @notice Tracks total mining rewards earned by each address
    mapping(address => uint256) public s_minerMineAmount;

    /// @notice Reserved storage gap for future upgrades (following OpenZeppelin upgradeable pattern)
    uint256[99] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Restricts function access to only the NFT Manager contract
     * @dev Used to protect functions that should only be called by the NFT Manager
     */
    modifier onlyNftManager() {
        require(msg.sender == address(s_iNFTManager), "MessageManager: only nft manager can do this operate");
        _;
    }

    /**
     * @notice Initializes the contract with necessary addresses
     * @dev This function replaces the constructor for upgradeable contracts
     * @param _initialOwner Address that will own the contract
     * @param _fccAddress Address of the FCC token contract
     * @param _usdtTokenAddr Address of the USDT token contract
     * @param _NFTManagerAddr Address of the NFT Manager contract
     */
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

    /**
     * @notice Creates a new airdrop activity
     * @dev Transfers tokens from caller to contract and creates activity records
     * @param _businessName Name of the merchant creating the activity
     * @param _activityContent Description or title of the activity
     * @param _latitudeLongitude Geographic coordinates for the activity
     * @param _activityDeadLine Expiration timestamp (must be within 30 days from now)
     * @param _totalDropAmts Total amount of tokens to be distributed
     * @param _dropType Distribution type: 1 = equal amounts, 2 = random amounts
     * @param _dropNumber Number of drops available
     * @param _minDropAmt Minimum amount per drop (0 for type 1)
     * @param _maxDropAmt Maximum/fixed amount per drop
     * @param _tokenContractAddr Address of token to distribute (must be FCC or USDT)
     * @return success Boolean indicating if operation succeeded
     * @return activityId The ID of the newly created activity
     */
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

        // Transfer tokens to this contract for locking
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

    /**
     * @notice Finishes an activity and distributes mining rewards to the merchant
     * @dev Returns undistributed tokens to merchant and calculates mining rewards based on participation
     * @param _activityId The ID of the activity to finish
     * @return success Boolean indicating if operation succeeded
     *
     * Mining reward calculation:
     * - Only merchants with valid NFTs (Merchant or User) can earn rewards
     * - Rewards can only be claimed once per 24 hours
     * - Merchant NFT holders get full percentage, User NFT holders get 50%
     * - Reward = min(lower_of(alreadyDropAmts, alreadyDropNumber * 20) * percent / 100, maxMineAmtLimit)
     * - Mining percentage decreases as total mined amount increases (50% -> 40% -> 20% -> 10% -> 0%)
     */
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

        // Check eligibility for mining rewards: must have valid NFT and respect 24-hour cooldown
        if (
            s_isMint && ifReward()
                && (
                    s_iNFTManager.getMerchantNTFDeadline(_msgSender()) > block.timestamp
                        || s_iNFTManager.getUserNTFDeadline(_msgSender()) > block.timestamp
                )
        ) {
            // Get current mining parameters based on total mined amount
            uint8 currentMinePercent;
            uint256 merchantOnceMaxMineTmpAmt;
            uint256 userOnceMaxMineTmpAmt;
            (currentMinePercent, merchantOnceMaxMineTmpAmt, userOnceMaxMineTmpAmt) = getCurrentMinePercent();
            if (s_minePercent != currentMinePercent) {
                s_minePercent = currentMinePercent;
            }
            if (s_minePercent > 0 && address(s_FccTokenAddr) == ai.tokenContractAddr) {
                // User NFT holders get 50% discount on mining percentage
                uint8 percent = (
                    s_iNFTManager.getMerchantNTFDeadline(_msgSender()) > block.timestamp
                        ? s_minePercent
                        : s_minePercent / 2
                );

                uint256 maxMineAmtLimit = (
                    s_iNFTManager.getMerchantNTFDeadline(_msgSender()) > block.timestamp
                        ? merchantOnceMaxMineTmpAmt
                        : userOnceMaxMineTmpAmt
                );
                // Mining reward is based on the lower of: total drops or (number of participants * 20 FCC)
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
                        // Final mining reward - exhaust remaining supply
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

    /**
     * @notice Distributes tokens to a user as part of an activity
     * @dev Can only be called by the activity owner, each user can only receive one drop per activity
     * @param _activityId The ID of the activity
     * @param _userAccount The address of the user receiving the drop
     * @param _dropAmt The amount to drop (must be within min/max range for type 2, ignored for type 1)
     * @return success Boolean indicating if operation succeeded
     */
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

    /**
     * @notice Returns the total mining rewards earned by a specific address
     * @param _miner The address to query
     * @return Total amount of mining rewards accumulated
     */
    function getMinerMineAmount(address _miner) external view returns (uint256) {
        return s_minerMineAmount[_miner];
    }

    /**
     * @notice Deletes the mining amount record for a miner
     * @dev Can only be called by the NFT Manager contract
     * @param _miner The address whose mining record should be deleted
     */
    function deleteMinerMineAmount(address _miner) external onlyNftManager {
        delete s_minerMineAmount[_miner];
    }

    // ======================= INTERNAL FUNCTIONS =======================

    /**
     * @notice Initializes storage variables for the Event Manager
     * @dev Internal function called during contract initialization
     * @param _fccAddress Address of the FCC token contract
     * @param _usdtTokenAddr Address of the USDT token contract
     * @param _NFTManagerAddr Address of the NFT Manager contract
     */
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

    /**
     * @notice Calculates the current mining percentage and limits based on total mined amount
     * @dev Mining rewards decrease in tiers as more tokens are mined
     * @return currentMinePercent The mining percentage for the current tier
     * @return merchantOnceMaxMineTmpAmt Maximum mining amount per activity for Merchant NFT holders
     * @return userOnceMaxMineTmpAmt Maximum mining amount per activity for User NFT holders
     *
     * Tier structure:
     * - 0-30M mined: 50% mining rate, 60 FCC max (merchant), 6 FCC max (user)
     * - 30-100M mined: 40% mining rate, 30 FCC max (merchant), 3 FCC max (user)
     * - 100-200M mined: 20% mining rate, 15 FCC max (merchant), 2 FCC max (user)
     * - 200-300M mined: 10% mining rate, 8 FCC max (merchant), 1 FCC max (user)
     * - 300M+ mined: Mining disabled
     */
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

    /**
     * @notice Checks if the caller is eligible for mining rewards based on the 24-hour cooldown
     * @dev Returns true if caller has never mined or if 24 hours have passed since last mining
     * @return _ret True if eligible for rewards, false otherwise
     */
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
