// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInvestorSalePool {
    error NotSupportFccAmount();
    error NotSupportUsdtAmount();

    error TokenUsdtAmountNotEnough();
    error FccTokenAmountNotEnough();

    event SetVaultAddress(address _vaultAddress);
    event WithdrawUsdt(address indexed withdrawAddress, uint256 _amount);
    event BuyFishcakeCoin(address indexed buyer, uint256 USDTAmount, uint256 fishcakeCoinAmount);

    function buyFccAmount(uint256 fccAmount) external;
    function buyFccByUsdtAmount(uint256 tokenUsdtAmount) external;

    function setVaultAddress(address _vaultAddress) external;
    function withdrawUsdt(uint256 _amount) external;
}
