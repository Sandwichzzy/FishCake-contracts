// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDirectSalePool {
    function buyFccAmount(uint256 fccAmount) external;
    function buyFccByUsdAmount(uint256 tokenUsdtAmount) external;
}
