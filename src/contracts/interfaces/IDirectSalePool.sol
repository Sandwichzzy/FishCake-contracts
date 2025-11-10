// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDirectSalePool {
    error TokenUsdtBalanceNotEnough();
    error FishcakeTokenNotEnough();

    event BuyFishcakeCoin(address indexed buyer, uint256 payUsdtAmount, uint256 fccAmount);

    function buyFccAmount(uint256 fccAmount) external;
    function buyFccByUsdAmount(uint256 tokenUsdtAmount) external;
}
