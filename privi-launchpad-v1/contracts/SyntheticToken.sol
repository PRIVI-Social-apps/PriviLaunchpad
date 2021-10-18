// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./IWithdrawable.sol";
import "./Structs.sol";

/**
 * @notice implementation of the erc20 token for minimal proxy multiple deployments
 * @author Eric Nordelo
 */
contract SyntheticToken is ERC20, AccessControl, Initializable, IWithdrawable {
    uint256 public constant PRECISION = 1000000;
    uint256 private constant PRICE_PRECISION = 1000;
    bytes32 public constant WITHDRAW_MANAGER = keccak256("withdraw_manager");

    string private _proxiedName;
    string private _proxiedSymbol;

    FundingRoundsData[] private _fundingRoundsData;

    address public fundingToken;

    // solhint-disable-next-line
    constructor() ERC20("Privi Synthetic Token", "pST") {}

    /**
     * @notice initializes minimal proxy clone
     */
    function initialize(
        string calldata proxiedName,
        string calldata proxiedSymbol,
        AppFundingData calldata _appData,
        address _withdrawManagerAddress
    ) external initializer {
        _proxiedName = proxiedName;
        _proxiedSymbol = proxiedSymbol;
        fundingToken = _appData.fundingToken;

        require(_appData.fundingSyntheticRoundsData.length > 0, "Invalid rounds count");
        for (uint256 i; i < _appData.fundingSyntheticRoundsData.length; i++) {
            require(_appData.fundingSyntheticRoundsData[i].mintedTokens == 0, "Invalid data");
            require(_appData.fundingSyntheticRoundsData[i].tokenPrice < _appData.s, "Invalid distribution");
            _fundingRoundsData.push(_appData.fundingSyntheticRoundsData[i]);
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(WITHDRAW_MANAGER, _withdrawManagerAddress);
    }

    function name() public view virtual override returns (string memory) {
        return _proxiedName;
    }

    function symbol() public view virtual override returns (string memory) {
        return _proxiedSymbol;
    }

    function getRoundNumber() public view returns (uint256) {
        // solhint-disable-next-line
        uint256 currentTime = block.timestamp;
        if (
            currentTime < _fundingRoundsData[0].openingTime ||
            currentTime >
            _fundingRoundsData[_fundingRoundsData.length - 1].openingTime +
                _fundingRoundsData[_fundingRoundsData.length - 1].durationTime *
                1 days
        ) {
            return 0;
        }
        for (uint256 i; i < _fundingRoundsData.length; i++) {
            if (
                currentTime >= _fundingRoundsData[i].openingTime &&
                currentTime < _fundingRoundsData[i].openingTime + _fundingRoundsData[i].durationTime * 1 days
            ) {
                return i + 1;
            }
        }
        return 0;
    }

    /**
     * @notice transfer the amount of selected tokens to address
     */
    function withdrawTo(
        address account,
        uint256 amount,
        address token
    ) external override onlyRole(WITHDRAW_MANAGER) returns (bool) {
        uint256 balance = ERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insuficient funds");
        return (ERC20(token).transfer(account, amount));
    }

    /**
     * @notice allows app funding manager to burn tokens
     */
    function burn(address to, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(to, amount);
    }

    /**
     * @notice get current price of the tokens
     * @dev this return value should be divided by PRICE_PRECISION
     */
    function getTokenPrice() external view returns (uint256) {
        uint256 _roundId = getRoundNumber();
        require(_roundId != 0, "None open round");

        // the index is the id minus 1
        return _fundingRoundsData[_roundId - 1].tokenPrice;
    }

    /**
     * @notice allows investors to buy synthetic tokens specifiying the amount to get
     * @param _amount the amount to get
     */
    function buyTokensByAmountToGet(uint256 _amount) external {
        uint256 _roundId = getRoundNumber();
        require(_roundId != 0, "None open round");

        uint256 _roundIndex = _roundId - 1;

        require(
            _fundingRoundsData[_roundIndex].mintedTokens < _fundingRoundsData[_roundIndex].capTokenToBeSold,
            "All tokens sold"
        );
        require(
            _amount <=
                (_fundingRoundsData[_roundIndex].capTokenToBeSold -
                    _fundingRoundsData[_roundIndex].mintedTokens),
            "Insuficient tokens"
        );
        require(_amount > 0, "Invalid amount");

        uint256 _amountToPay = (_amount * _fundingRoundsData[_roundIndex].tokenPrice) / PRICE_PRECISION;

        _mint(msg.sender, _amount);
        _fundingRoundsData[_roundIndex].mintedTokens += _amount;

        bool result = ERC20(fundingToken).transferFrom(msg.sender, address(this), _amountToPay);
        // solhint-disable-next-line
        require(result);
    }

    /**
     * @notice allows investors to buy synthetic tokens specifiying the amount to pay
     * @param _amountToPay the amount to pay
     */
    function buyTokensByAmountToPay(uint256 _amountToPay) external {
        uint256 _roundId = getRoundNumber();
        require(_roundId != 0, "None open round");

        uint256 _roundIndex = _roundId - 1;

        require(
            _fundingRoundsData[_roundIndex].mintedTokens < _fundingRoundsData[_roundIndex].capTokenToBeSold,
            "All tokens sold"
        );
        uint256 _amount = (_amountToPay * PRICE_PRECISION) / _fundingRoundsData[_roundIndex].tokenPrice;
        require(_amount > 0, "Insuficient amount");
        require(
            _amount <=
                (_fundingRoundsData[_roundIndex].capTokenToBeSold -
                    _fundingRoundsData[_roundIndex].mintedTokens),
            "Insuficient tokens"
        );

        _mint(msg.sender, _amount);
        _fundingRoundsData[_roundIndex].mintedTokens += _amount;

        bool result = ERC20(fundingToken).transferFrom(msg.sender, address(this), _amountToPay);
        // solhint-disable-next-line
        require(result);
    }
}
