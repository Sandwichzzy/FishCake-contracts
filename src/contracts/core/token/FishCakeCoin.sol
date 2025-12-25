// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

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
    uint256 public constant MAXTOTAL_SUPPLY = 1_000_000_000 * (10 ** 6);

    uint256 public s_redemptionPoolBurnedTokens; // Only tracks redemption pool burns

    address public s_RedemptionPool;

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

    modifier onlyRedemptionPool() {
        require(
            msg.sender == s_RedemptionPool,
            "FishCakeCoin onlyRedemptionPool: Only RedemptionPool can call this function"
        );
        _;
    }

    function initialize(address _owner, address _RedemptionPool) public initializer {
        require(_owner != address(0), "FishCakeCoin initialize _owner can't be zero address");
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init(_owner);
        s_RedemptionPool = _RedemptionPool;
        _transferOwnership(_owner);
        s_isAllocation = false;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function FccBalance(address _address) external view returns (uint256) {
        return balanceOf(_address);
    }

    function setRedemptionPool(address _RedemptionPool) external onlyOwner {
        s_RedemptionPool = _RedemptionPool;
    }

    function setPoolAddress(fishCakePool memory _pool) external onlyOwner {
        _beforeAllocation();
        _beforePoolAddress(_pool);
        s_fcPool = _pool;
    }

    function poolAllocate() external onlyOwner {
        _beforeAllocation();
        _mint(s_fcPool.miningPool, (MAXTOTAL_SUPPLY * 3) / 10); // 30% of total supply
        _mint(s_fcPool.directSalePool, (MAXTOTAL_SUPPLY * 2) / 10); // 20% of total supply
        _mint(s_fcPool.investorSalePool, MAXTOTAL_SUPPLY / 10); // 10% of total supply
        _mint(s_fcPool.nftSalesRewardsPool, (MAXTOTAL_SUPPLY * 2) / 10); // 20% of total supply
        _mint(s_fcPool.ecosystemPool, MAXTOTAL_SUPPLY / 10); // 10% of total supply
        _mint(s_fcPool.foundationPool, MAXTOTAL_SUPPLY / 10); // 10% of total supply
    }

    function burn(address user, uint256 _amount) external onlyRedemptionPool {
        _burn(user, _amount);
        s_redemptionPoolBurnedTokens += _amount;
        emit Burn(_amount, totalSupply());
    }

    function FccTotalSupply() external view returns (uint256) {
        return totalSupply();
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
