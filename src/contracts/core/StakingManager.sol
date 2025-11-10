// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IFishCakeEventManager.sol";
import "../interfaces/INftManager.sol";
import "../interfaces/IStakingManager.sol";

contract StakingManage is IStakingManager, Initializable, OwnableUpgradeable, ReentrancyGuard {
    uint256 public constant MIN_STAKE_AMT = 10 * 10 ** 6;

    uint256 public constant LOCK_THIRTYDAYS = 30 days;

    uint256 public constant LOCK_SIXTYDAYS = 60 days;

    uint256 public constant LOCK_NINETYDAYS = 90 days;

    uint256 public constant LOCK_HALFYEARS = 180 days;

    uint256 public constant LOCK_ONEYEARS = 360 days;

    /// @dev timestamp for 2025-10-31 00:00:00 UTC 过了这个时间之后，APR减半
    uint256 public s_halfAprTimeStamp = 1767225600;

    uint256 public s_aprOffset = 1000;

    uint256 public s_dayTimeStamp = 86400;

    uint256 public s_totalStakingAmount;

    address public s_fccAddress;

    uint256 public s_messageNonce;

    IFishCakeEventManager public s_feManagerAddress;

    INftManager public s_nftManagerAddress;

    // ==================== struct =============================
    struct stakeHolderStakingInfo {
        uint256 startStakingTime;
        uint256 amount;
        uint256 messageNonce;
        uint256 endStakingTime;
        uint8 stakingStatus;
        uint8 stakingType;
        uint256 bindingNft;
    }

    mapping(address => mapping(bytes32 => stakeHolderStakingInfo)) s_stakingQueued;

    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function initialize(address _initialOwner, IFishCakeEventManager _feManagerAddress, INftManager _nftManagerAddress)
        public
        initializer
    {
        require(_initialOwner != address(0), "StakingManager initialize: _initialOwner can't be zero address");
        __Ownable_init(_initialOwner);
        _transferOwnership(_initialOwner);
        s_feManagerAddress = _feManagerAddress;
        s_nftManagerAddress = _nftManagerAddress;
        s_messageNonce = 0;
    }

    function DepositIntoStaking(uint256 amount, uint8 stakingType) external nonReentrant {
        require(
            amount > MIN_STAKE_AMT, "StakingManager DepositIntoStaking: staking amount must be more than minStakeAmount"
        );
        IERC20(s_fccAddress).safeTransfer(address(this), amount);
        bytes32 txMessageHash = keccak256(abi.encode(msg.sender, s_fccAddress, amount, s_messageNonce));
        uint256 stakingTimestamp = 0;
        uint256 apr = 0;
        (stakingTimestamp, apr) = getStakingPeriodAndApr(stakingType);
        uint256 endTime = block.timestamp + stakingTimestamp;

        uint256 tokenId = s_nftManagerAddress.getActiveMinerBoosterNft(msg.sender);

        stakeHolderStakingInfo memory ssInfo = stakeHolderStakingInfo({
            startStakingTime: block.timestamp,
            amount: amount,
            messageNonce: s_messageNonce,
            endStakingTime: endTime,
            stakingStatus: 0, // under staking now
            stakingType: stakingType,
            bindingNft: tokenId
        });
        //boosterNFT一次性使用，不可重复使用
        s_nftManagerAddress.inActiveMinerBoosterNft(msg.sender);
        s_stakingQueued[msg.sender][txMessageHash] = ssInfo;
        s_totalStakingAmount += amount;

        emit StakeHolderDepositStaking(msg.sender, amount, s_messageNonce);

        s_messageNonce++;
    }

    function withdrawFromStakingWithAprIncome(uint256 amount, uint256 messageNonce) external nonReentrant {
        bytes32 txMessageHash = keccak256(abi.encode(msg.sender, s_fccAddress, amount, messageNonce));
        uint256 txLockEndTime = s_stakingQueued[msg.sender][txMessageHash].endStakingTime;
        if (block.timestamp < txLockEndTime) {
            revert FundingUnderStaking(amount, txLockEndTime);
        }
        uint256 amountOut = s_stakingQueued[msg.sender][txMessageHash].amount;
        if (amountOut < MIN_STAKE_AMT) {
            revert NoFundingForStaking();
        }
        s_totalStakingAmount -= amount;
        s_stakingQueued[msg.sender][txMessageHash].stakingStatus = 1; //staking end

        uint256 rewardAprFunding = calculateArpFunding(
            s_stakingQueued[msg.sender][txMessageHash].amount,
            s_stakingQueued[msg.sender][txMessageHash].stakingType,
            s_stakingQueued[msg.sender][txMessageHash].startStakingTime,
            s_stakingQueued[msg.sender][txMessageHash].bindingNft
        );

        IERC20(s_fccAddress).safeTransfer(msg.sender, amount);
        IERC20(s_fccAddress).safeTransfer(msg.sender, rewardAprFunding);

        emit StakeHolderWithdrawStaking(msg.sender, amount, messageNonce, txMessageHash);
    }

    function getStakingAprFunding(uint256 amount, uint256 messageNonce) external view returns (uint256) {
        bytes32 txMessageHash = keccak256(abi.encode(msg.sender, s_fccAddress, amount, messageNonce));

        uint256 rewardAprFunding = calculateArpFunding(
            s_stakingQueued[msg.sender][txMessageHash].amount,
            s_stakingQueued[msg.sender][txMessageHash].stakingType,
            s_stakingQueued[msg.sender][txMessageHash].startStakingTime,
            s_stakingQueued[msg.sender][txMessageHash].bindingNft
        );
        return rewardAprFunding;
    }

    //==========================internal function===============================
    function calculateArpFunding(uint256 stakingAmount, uint8 stakingType, uint256 startStakingTime, uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        uint256 stakingArp = 0;
        uint256 lockType = 0;
        uint256 nftApr = getNftApr(tokenId);
        (lockType, stakingArp) = getStakingPeriodAndApr(stakingType);
        uint256 totalRewardApr = nftApr + stakingArp;
        uint256 actualStakingDuration = block.timestamp - startStakingTime;
        if (block.timestamp >= s_halfAprTimeStamp) {
            uint256 reward = stakingAmount * totalRewardApr * actualStakingDuration / (100 * 365 days);
            return reward / 2;
        }
        return stakingAmount * totalRewardApr * actualStakingDuration / (100 * 365 days);
    }

    function getNftApr(uint256 tokenId) internal view returns (uint256) {
        require(tokenId != 0, "StakingManager getNftApr: tokenId can't be zero");
        uint8 nftType = s_nftManagerAddress.getMinerBoosterNftType(tokenId);
        if (nftType == 6) {
            return 20;
        } else if (nftType == 5) {
            return 15;
        } else if (nftType == 4) {
            return 9;
        } else if (nftType == 3) {
            return 5;
        } else {
            return 1;
        }
    }

    function getStakingPeriodAndApr(uint8 stakingType) internal pure returns (uint256, uint256) {
        require(
            stakingType > 0 && stakingType < 5,
            "StakingManager getStakingPeriod: stakingType amount must be more than 0 and less than 4"
        );
        if (stakingType == 1) {
            return (LOCK_THIRTYDAYS, 3);
        } else if (stakingType == 2) {
            return (LOCK_SIXTYDAYS, 6);
        } else if (stakingType == 3) {
            return (LOCK_NINETYDAYS, 9);
        } else {
            return (LOCK_HALFYEARS, 15);
        }
    }
}
