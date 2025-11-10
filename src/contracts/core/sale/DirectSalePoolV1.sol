// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../interfaces/IDirectSalePool.sol";
import "../../interfaces/IRedemptionPool.sol";

contract DirectSalePoolV1 is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    IERC20 public s_fishCakeCoin;
    IRedemptionPool public s_redemptionPool;
    IERC20 public s_tokenUsdtAddress;

    uint256 public s_totalSellFccAmount;
    uint256 public s_totalReceiveUsdtAmount;

    error TokenUsdtBalanceNotEnough();
    error FishcakeTokenNotEnough();

    event BuyFishcakeCoin(address indexed buyer, uint256 payUsdtAmount, uint256 fccAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _fishCakeCoin,
        address _redemptionPool,
        address _tokenUsdtAddress
    ) public initializer {
        require(_initialOwner != address(0), "DirectSalePool initialize: _initialOwner can't be zero address");
        __ERC20_init("FishCake", "FCC");
        __Ownable_init(_initialOwner);
        _transferOwnership(_initialOwner);

        s_fishCakeCoin = IERC20(_fishCakeCoin);
        s_redemptionPool = IRedemptionPool(_redemptionPool);
        s_tokenUsdtAddress = IERC20(_tokenUsdtAddress);
        s_totalSellFccAmount = 0;
        s_totalReceiveUsdtAmount = 0;
    }

    function buyFccAmount(uint256 fccAmount) external {
        require(
            s_fishCakeCoin.balanceOf(address(this)) >= fccAmount, "DirectSalePool buyFccAmount: fcc token is not enough"
        );
        uint256 payUsdtAmount = fccAmount / 10;
        if (s_tokenUsdtAddress.balanceOf(msg.sender) < payUsdtAmount) {
            revert TokenUsdtBalanceNotEnough();
        }

        s_totalSellFccAmount += fccAmount;
        s_totalReceiveUsdtAmount += payUsdtAmount;

        s_tokenUsdtAddress.transferFrom(msg.sender, address(s_redemptionPool), payUsdtAmount);

        s_fishCakeCoin.transfer(msg.sender, fccAmount);

        emit BuyFishcakeCoin(msg.sender, payUsdtAmount, fccAmount);
    }

    function buyFccByUsdtAmount(uint256 tokenUsdtAmount) external {
        require(
            s_tokenUsdtAddress.balanceOf(msg.sender) >= tokenUsdtAmount,
            "DirectSalePool buyFccAmount: usdt token is not enough"
        );
        uint256 sellFccAmount = tokenUsdtAmount * 10; // 1 USDT = 10 FCC
        if (sellFccAmount > s_fishCakeCoin.balanceOf(address(this))) {
            revert FishcakeTokenNotEnough();
        }

        s_totalSellFccAmount += sellFccAmount;
        s_totalReceiveUsdtAmount += tokenUsdtAmount;

        s_tokenUsdtAddress.transferFrom(msg.sender, address(s_redemptionPool), tokenUsdtAmount);
        s_fishCakeCoin.transfer(msg.sender, sellFccAmount);

        emit BuyFishcakeCoin(msg.sender, tokenUsdtAmount, sellFccAmount);
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
        return true;
    }
}
