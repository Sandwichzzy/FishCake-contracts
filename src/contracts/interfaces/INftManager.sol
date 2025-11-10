// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface INftManager {
    error WithdrawNativeTokenFail(address to, uint256 amount);
    error MineAmountNotEnough(uint256 amount);

    event UriPrefixSet(address indexed setterAddress, string urlPrefix);

    event SetValues(address indexed _setterAddress, uint256 _merchantValue, uint256 _userValue);

    event CreateNFT(
        address indexed creator,
        uint256 _tokenId,
        string _businessName,
        string _description,
        string _imgUrl,
        string _businessAddress,
        string _webSite,
        string _social,
        uint256 _value,
        uint256 _deadline,
        uint8 _type
    );

    event WithdrawUToken(
        address indexed withdrawer, address indexed _tokenAddr, address indexed _account, uint256 _value
    );

    event SetValidTime(address indexed setter, uint256 _time);

    event Withdraw(address indexed withdrawer, uint256 _amount);
    event Received(address indexed receiver, uint256 _value);

    event UpdatedNftJson(address indexed creator, uint8 nftType, string newJsonUrl);
    event NameSymbolUpdated(string newName, string newSymbol);

    function createNft(
        string memory _businessName,
        string memory _description,
        string memory _imgUrl,
        string memory _businessAddress,
        string memory _website,
        string memory _social,
        uint8 _type
    ) external returns (bool, uint256);

    function mintBoosterNFT(address miner) external returns (bool, uint256);
    function setUriPrefix(string memory _uriPrefix) external;
    function setValues(uint256 _merchantValue, uint256 _userValue) external;
    function withdrawToken(address _tokenAddr, address _account, uint256 _value) external returns (bool);

    function withdrawNativeToken(address payable _recipient, uint256 _amount) external returns (bool);
    function getMerchantNTFDeadline(address _account) external view returns (uint256);
    function getUserNTFDeadline(address _account) external view returns (uint256);
    function inActiveMinerBoosterNft(address _miner) external;
    function getActiveMinerBoosterNft(address _miner) external view returns (uint256);
    function getMinerBoosterNftType(uint256 tokenId) external view returns (uint8);
}
