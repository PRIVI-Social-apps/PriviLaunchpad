// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IWithdrawable.sol";
import "./Structs.sol";

/**
 * @notice implementation of the erc20 token for minimal proxy multiple deployments
 * @author Eric Nordelo
 */
contract RangeToken is ERC20, AccessControl, Initializable, IWithdrawable {
    uint256 public constant PRECISION = 1000000;
    uint256 private constant PRICE_PRECISION = 1000;
    bytes32 public constant WITHDRAW_MANAGER = keccak256("withdraw_manager");

    address private _fundingToken;

    uint256 private _rMin;
    uint256 private _rMax;
    uint256 private _s;
    uint256 private _x;
    uint256 private _y;

    string private _proxiedName;
    string private _proxiedSymbol;

    FundingRoundsData[] private _fundingRoundsData;

    uint256 public maturityDate; // dte of maturity of the options

    // this value should be set by oracles
    uint256 public estimatedPriceAtMaturityDate;

    // solhint-disable-next-line
    constructor() ERC20("Privi Range Token Implementation", "pRTI") {}

    /**
     * @notice initializes the minimal proxy clone
     * @dev ! INSERTING AN ARRAY OF STRUCTS, VERY EXPENSIVE!!!
     * @param _name the name of the token
     * @param _symbol the symbol of the token
     * @param _appData the app data
     */
    function initialize(
        string calldata _name,
        string calldata _symbol,
        AppFundingData calldata _appData,
        address _withdrawManagerAddress
    ) external initializer {
        _proxiedName = _name;
        _proxiedSymbol = _symbol;

        _fundingToken = _appData.fundingToken;

        // initialize variables
        _s = _appData.s;
        _rMin = _appData.rMin;
        _rMax = _appData.rMax;
        estimatedPriceAtMaturityDate = _appData.rMax;
        _x = _appData.x;
        _y = _appData.y;

        maturityDate = _appData.maturity;

        // TODO: check the interval with the black scholes function

        require(_appData.fundingRangeRoundsData.length > 0, "Invalid rounds count");
        for (uint256 i; i < _appData.fundingRangeRoundsData.length - 1; i++) {
            require(_appData.fundingRangeRoundsData[i].mintedTokens == 0, "Invalid data");
            require(
                _appData.fundingRangeRoundsData[i + 1].tokenPrice >=
                    _appData.fundingRangeRoundsData[i].tokenPrice,
                "Invalid distribution"
            );
            _fundingRoundsData.push(_appData.fundingRangeRoundsData[i]);
        }
        require(
            _appData.fundingRangeRoundsData[_appData.fundingRangeRoundsData.length - 1].mintedTokens == 0,
            "Invalid data"
        );
        _fundingRoundsData.push(_appData.fundingRangeRoundsData[_appData.fundingRangeRoundsData.length - 1]);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(WITHDRAW_MANAGER, _withdrawManagerAddress);
    }

    function name() public view virtual override returns (string memory) {
        return _proxiedName;
    }

    function symbol() public view virtual override returns (string memory) {
        return _proxiedSymbol;
    }

    /**
     * @notice allows app funding manager to burn tokens
     */
    function burn(address to, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(to, amount);
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
     * @notice returns the estimated payout at the time
     * @dev the actual value should be divided by precision
     */
    function currentEstimatedPayout() public view returns (uint256) {
        if (estimatedPriceAtMaturityDate < _rMin) {
            return (_s * PRECISION) / _rMin;
        } else if (estimatedPriceAtMaturityDate > _rMax) {
            return (_s * PRECISION) / _rMax;
        } else {
            return (_s * PRECISION) / estimatedPriceAtMaturityDate;
        }
    }

    /**
     * @notice returns the balance and the payout at the time
     */
    function balanceAndPayoutOf(address _holder) external view returns (uint256 balance, uint256 payout) {
        balance = balanceOf(_holder);
        payout = currentEstimatedPayout();
    }

    /**
     * @notice get current price of the tokens
     * @dev the return value should be divided by PRICE_PRECISION
     */
    function getTokenPrice() external view returns (uint256) {
        uint256 _roundId = getRoundNumber();
        require(_roundId != 0, "None open round");

        // the index is the id minus 1
        return _fundingRoundsData[_roundId - 1].tokenPrice;
    }

    /**
     * @notice returns the index of the active round or zero if there is none
     */
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
     * @dev allow to investors buy range tokens specifiying the amount of range tokens
     * @param _amount allow to the investors that buy range token specifying the amount
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

        uint256 _amountToPay = (_amount * _fundingRoundsData[_roundIndex].tokenPrice) / PRICE_PRECISION;

        _mint(msg.sender, _amount);
        _fundingRoundsData[_roundIndex].mintedTokens += _amount;

        bool result = ERC20(_fundingToken).transferFrom(msg.sender, address(this), _amountToPay);
        // solhint-disable-next-line
        require(result);
    }

    /**
     * @dev allow to investors buy range tokens specifiying the amount of pay tokens
     * @param _amountToPay allow to the investors that buy range token specifying the amount of pay token
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
        require(_amount > 0, "Insuficient amount to pay");
        require(
            _amount <=
                (_fundingRoundsData[_roundIndex].capTokenToBeSold -
                    _fundingRoundsData[_roundIndex].mintedTokens),
            "Insuficient tokens"
        );

        _mint(msg.sender, _amount);
        _fundingRoundsData[_roundIndex].mintedTokens += _amount;

        bool result = ERC20(_fundingToken).transferFrom(msg.sender, address(this), _amountToPay);
        // solhint-disable-next-line
        require(result);
    }
}
