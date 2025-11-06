// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract FishCakeCoin is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard
{
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * (10 ** 6);

    uint256 public s_burnedTokens;

    address public s_redemptionPool;

    bool internal s_isAllocation;

    struct fishCakePool {
        address miningPool;
        address directSalePool;
        address investorSalePool;
        address nftSalesRewardsPool;
        address ecosystemPool;
        address foundationPool;
        address redemptionPool;
    }

    fishCakePool public s_fcPool;

    event Burn(uint256 _burnAmount, uint256 _totalSupply);

    uint256[100] private __gap;

    string private constant NAME = "FishCake Coin";
    string private constant SYMBOL = "FCC";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _RedemptionPool) public initializer {
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init();
        _mint(address(this), TOTAL_SUPPLY);
    }

    // ==================== internal function =============================
    function _beforeAllocation() internal virtual {
        require(!s_isAllocation, "FishCakeCoin _beforeAllocation:Fishcake is already allocate");
    }

    function _beforePoolAddress(fishCakePool memory _fcPool) internal virtual {
        require(_fcPool.miningPool != address(0), "FishCakeCoin _beforeAllocation:Missing allocate MiningPool address");
        require(
            _fcPool.directSalePool != address(0),
            "FishCakeCoin _beforeAllocation:Missing allocate DirectSalePool address"
        );
        require(
            _fcPool.investorSalePool != address(0),
            "FishCakeCoin _beforeAllocation:Missing allocate InvestorSalePool address"
        );
        require(
            _fcPool.nftSalesRewardsPool != address(0),
            "FishCakeCoin _beforeAllocation:Missing allocate NFTSalesRewardsPool address"
        );
        require(
            _fcPool.ecosystemPool != address(0), "FishCakeCoin _beforeAllocation:Missing allocate EcosystemPool address"
        );
        require(
            _fcPool.foundationPool != address(0),
            "FishCakeCoin _beforeAllocation:Missing allocate FoundationPool address"
        );
    }
}
