// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IWithdrawable.sol";
import "./ScopeToken.sol";
import "./StakeToken.sol";
import "./Structs.sol";

/**
 * @notice implementation of the insurance contract for minimal proxy deployments
 * @author Eric Nordelo
 */
contract Insurance is AccessControl, Initializable, IWithdrawable {
    bytes32 private constant STAKE_TOKEN = keccak256("STAKE_TOKEN");
    bytes32 private constant SCOPE_TOKEN = keccak256("SCOPE_TOKEN");
    bytes32 private constant WITHDRAW_MANAGER = keccak256("WITHDRAW_MANAGER");

    address public appTokenAddress;
    address public stakeTokenAddress;
    address public scopeTokenAddress;

    uint256 public unlockingDate;

    // solhint-disable-next-line
    constructor() {}

    /**
     * @notice initializes the minimal proxy clone (setup roles)
     */
    function initialize(
        address _appTokenAddress,
        address _stakeTokenAddress,
        address _scopeTokenAddress,
        address _withdrawManagerAddress,
        uint256 _maturity,
        uint256 _t
    ) external initializer {
        if (_maturity > _t) {
            unlockingDate = _maturity;
        } else {
            unlockingDate = _t;
        }

        appTokenAddress = _appTokenAddress;
        stakeTokenAddress = _stakeTokenAddress;
        scopeTokenAddress = _scopeTokenAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(STAKE_TOKEN, _stakeTokenAddress);
        _setupRole(SCOPE_TOKEN, _scopeTokenAddress);
        _setupRole(WITHDRAW_MANAGER, _withdrawManagerAddress);
    }

    /**
     * @notice returns the balance available for owners to withdraw at the moment,
     * before the unlocking date of stake and scope tokens the value is 0
     * @return the available balance in app tokens
     */
    function withdrawableBalance() public view returns (uint256) {
        // solhint-disable-next-line
        if (unlockingDate > block.timestamp) {
            return 0;
        }

        uint256 totalBalance = IERC20(appTokenAddress).balanceOf(address(this));
        uint256 owedValueInScopeTokens = ScopeToken(scopeTokenAddress).getAppTokensOwed();
        uint256 owedValueInStakeTokens = StakeToken(stakeTokenAddress).appTokensOwed();

        if (totalBalance > owedValueInScopeTokens + owedValueInStakeTokens) {
            return totalBalance - (owedValueInScopeTokens + owedValueInStakeTokens);
        } else {
            return 0;
        }
    }

    /**
     * @dev allows to claim through the token contracts
     */
    function sendAppTokens(address _to, uint256 _amount) external returns (bool) {
        if (hasRole(STAKE_TOKEN, msg.sender) || hasRole(SCOPE_TOKEN, msg.sender)) {
            return (IERC20(appTokenAddress).transfer(_to, _amount));
        } else {
            revert("Invalid caller");
        }
    }

    /**
     * @notice transfer the amount of selected tokens to address
     */
    function withdrawTo(address account, uint256 amount)
        external
        override
        onlyRole(WITHDRAW_MANAGER)
        returns (bool)
    {
        uint256 balance = withdrawableBalance();
        require(balance >= amount, "Insuficient withdrawable funds");
        return (IERC20(appTokenAddress).transfer(account, amount));
    }
}
