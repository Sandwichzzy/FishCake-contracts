// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../interfaces/IRedemptionPool.sol";
import "../../interfaces/IInvestorSalePool.sol";

contract InvestorSalePool is
    Initializable,
    IInvestorSalePool,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    uint256 public constant USDT_DECIMALS = 6;
    uint256 public constant FCC_DECIMALS = 6;

    IERC20 public s_fishCakeCoin;
    IRedemptionPool public s_redemptionPool;
    IERC20 public s_tokenUsdtAddress;

    address public s_vaultAddress;

    uint256 public s_totalSellFccAmount;
    uint256 public s_totalReceiveUsdtAmount;

    uint256[100] private __gap;

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
        require(_initialOwner != address(0), "InvestorSalePool initialize: _initialOwner can't be zero address");
        __Ownable_init(_initialOwner);
        _transferOwnership(_initialOwner);

        s_fishCakeCoin = IERC20(_fishCakeCoin);
        s_redemptionPool = IRedemptionPool(_redemptionPool);
        s_tokenUsdtAddress = IERC20(_tokenUsdtAddress);
        s_totalSellFccAmount = 0;
        s_totalReceiveUsdtAmount = 0;
    }

    function buyFccAmount(uint256 fccAmount) external {
        if (fccAmount > s_fishCakeCoin.balanceOf(address(this))) {
            revert FccTokenAmountNotEnough();
        }
        uint256 tokenUsdtAmount = calculateUsdtByFcc(fccAmount);
        if (s_tokenUsdtAddress.balanceOf(msg.sender) < tokenUsdtAmount) {
            revert TokenUsdtAmountNotEnough();
        }

        s_totalSellFccAmount += fccAmount;
        s_totalReceiveUsdtAmount += tokenUsdtAmount;

        s_tokenUsdtAddress.transferFrom(msg.sender, address(this), tokenUsdtAmount / 2);
        //销售获得的一半USDT转到RedemptionPool合约中
        s_tokenUsdtAddress.transferFrom(msg.sender, address(s_redemptionPool), tokenUsdtAmount / 2);

        s_fishCakeCoin.transfer(msg.sender, fccAmount);

        emit BuyFishcakeCoin(msg.sender, tokenUsdtAmount, fccAmount);
    }

    function buyFccByUsdtAmount(uint256 tokenUsdtAmount) external {
        if (s_tokenUsdtAddress.balanceOf(msg.sender) < tokenUsdtAmount) {
            revert TokenUsdtAmountNotEnough();
        }
        uint256 fccAmount = calculateFccByUsdt(tokenUsdtAmount);
        if (fccAmount > s_fishCakeCoin.balanceOf(address(this))) {
            revert FccTokenAmountNotEnough();
        }
        s_totalSellFccAmount += fccAmount;
        s_totalReceiveUsdtAmount += tokenUsdtAmount;

        s_tokenUsdtAddress.transferFrom(msg.sender, address(this), tokenUsdtAmount / 2);
        s_tokenUsdtAddress.transferFrom(msg.sender, address(s_redemptionPool), tokenUsdtAmount / 2);

        s_fishCakeCoin.transfer(msg.sender, fccAmount);

        emit BuyFishcakeCoin(msg.sender, tokenUsdtAmount, fccAmount);
    }

    function setVaultAddress(address _vaultAddress) external onlyOwner {
        s_vaultAddress = _vaultAddress;
        emit SetVaultAddress(_vaultAddress);
    }

    function withdrawUsdt(uint256 _amount) external onlyOwner {
        s_tokenUsdtAddress.safeTransfer(s_vaultAddress, _amount);
        emit WithdrawUsdt(s_vaultAddress, _amount);
    }

    function calculateFccByUsdtExternal(uint256 _amount) external pure returns (uint256) {
        return calculateFccByUsdt(_amount);
    }

    function calculateFccByUsdt(uint256 _usdtAmount) internal pure returns (uint256) {
        if (_usdtAmount >= 100_000 * USDT_DECIMALS) {
            // Tier 1: 1 FCC = 0.06 USDT
            return (_usdtAmount * 100 * FCC_DECIMALS) / (6 * USDT_DECIMALS);
        } else if (_usdtAmount < 100_000 * USDT_DECIMALS && _usdtAmount >= 10_000 * USDT_DECIMALS) {
            // Tier 2: 1 FCC = 0.07 USDT
            return (_usdtAmount * 100 * FCC_DECIMALS) / (7 * USDT_DECIMALS);
        } else if (_usdtAmount < 10_000 * USDT_DECIMALS && _usdtAmount >= 5_000 * USDT_DECIMALS) {
            // Tier 3: 1 FCC = 0.08 USDT
            return (_usdtAmount * 100 * FCC_DECIMALS) / (8 * USDT_DECIMALS);
        } else if (_usdtAmount < 5_000 * USDT_DECIMALS && _usdtAmount >= 1_000 * USDT_DECIMALS) {
            // Tier 4: 1 FCC = 0.09 USDT
            return (_usdtAmount * 100 * FCC_DECIMALS) / (9 * USDT_DECIMALS);
        } else if (_usdtAmount < 1_000 * USDT_DECIMALS && _usdtAmount > 0 * USDT_DECIMALS) {
            // Tier 5: 1 FCC = 0.1 USDT
            return (_usdtAmount * 10 * FCC_DECIMALS) / USDT_DECIMALS;
        } else {
            revert NotSupportUsdtAmount();
        }
    }

    function calculateUsdtByFccExternal(uint256 _amount) external pure returns (uint256) {
        return calculateUsdtByFcc(_amount);
    }

    function calculateUsdtByFcc(uint256 _fccAmount) internal pure returns (uint256) {
        if (_fccAmount >= 5_000_000 * FCC_DECIMALS) {
            // Tier 1: 1 FCC = 0.06 USDT
            return (_fccAmount * 6 * USDT_DECIMALS) / (100 * FCC_DECIMALS);
        } else if (_fccAmount < 5_000_000 * FCC_DECIMALS && _fccAmount >= 250_000 * FCC_DECIMALS) {
            // Tier 2: 1 FCC = 0.07 USDT
            return (_fccAmount * 7 * USDT_DECIMALS) / (100 * FCC_DECIMALS);
        } else if (_fccAmount < 250_000 * FCC_DECIMALS && _fccAmount >= 100_000 * FCC_DECIMALS) {
            // Tier 3: 1 FCC = 0.08 USDT
            return (_fccAmount * 8 * USDT_DECIMALS) / (100 * FCC_DECIMALS);
        } else if (_fccAmount < 100_000 * FCC_DECIMALS && _fccAmount >= 16_666 * FCC_DECIMALS) {
            // Tier 4: 1 FCC = 0.09 USDT
            return (_fccAmount * 9 * USDT_DECIMALS) / (100 * FCC_DECIMALS);
        } else if (_fccAmount < 16_666 * FCC_DECIMALS && _fccAmount > 0 * FCC_DECIMALS) {
            // Tier 5: 1 FCC = 0.1 USDT
            return (_fccAmount * USDT_DECIMALS) / (10 * FCC_DECIMALS);
        } else {
            revert NotSupportFccAmount();
        }
    }
}
