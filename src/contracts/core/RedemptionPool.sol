// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IRedemptionPool.sol";
import "./token/FishCakeCoin.sol";

contract RedemptionPool is IRedemptionPool, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable i_fishCakeCoin;
    IERC20 public immutable i_usdtToken;
    uint256 public immutable unlockTime = block.timestamp + 1095 days;

    error USDTAmountIsZero();
    error NotEnoughUSDT();

    event ClaimSuccess(address indexed user, uint256 tokenUsdtAmount, uint256 fishcakeCoinAmount);

    constructor(address _fishCakeCoin, address _usdtToken) {
        i_fishCakeCoin = IERC20(_fishCakeCoin);
        i_usdtToken = IERC20(_usdtToken);
    }

    function claim(uint256 _amount) external {
        require(block.timestamp >= unlockTime, "RedemptionPool claim: redemption is locked");
        require(i_fishCakeCoin.balanceOf(msg.sender) >= _amount, "RedemptionPool claim: fcc balance is not enough");
        uint256 usdtAmount = calculateUsdt(_amount);
        if (usdtAmount == 0) {
            revert USDTAmountIsZero();
        }
        if (usdtAmount > balance()) {
            revert NotEnoughUSDT();
        }
        FishCakeCoin(address(i_fishCakeCoin)).burn(msg.sender, _amount);
        i_usdtToken.safeTransfer(msg.sender, usdtAmount);
        emit ClaimSuccess(msg.sender, usdtAmount, _amount);
    }

    // ==================== internal function =============================
    function balance() internal view returns (uint256) {
        return i_usdtToken.balanceOf(address(this));
    }

    function calculateUsdt(uint256 _amount) internal view returns (uint256) {
        // USDT balance / fishcakeCoin total supply
        return i_usdtToken.balanceOf(address(this)) * _amount / i_fishCakeCoin.totalSupply();
    }
}
