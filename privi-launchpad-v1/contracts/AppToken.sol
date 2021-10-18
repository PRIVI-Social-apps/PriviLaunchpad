// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./AppFundingManager.sol";

/**
 * @notice implementation of the erc20 token for minimal proxy multiple deployments
 * @author Eric Nordelo
 */
contract AppToken is ERC20, AccessControl, Initializable {
    string private _proxiedName;
    string private _proxiedSymbol;

    address private _appFundingManagerAddress;

    uint256 public appId;
    uint256 public appTokenLaunchingDate;
    string public logoIPFSHash;

    event ClaimTokens(address indexed holder, uint256 balance);

    // solhint-disable-next-line
    constructor() ERC20("Privi APP Token", "pAT") {}

    /**
     * @notice initializes the minimal proxy clone
     */
    function initialize(
        string calldata proxiedName,
        string calldata proxiedSymbol,
        string calldata _ipfsHashForLogo,
        uint256 _appId,
        uint256 _appTokenLaunchingDate
    ) external initializer {
        _proxiedName = proxiedName;
        _proxiedSymbol = proxiedSymbol;
        appTokenLaunchingDate = _appTokenLaunchingDate;

        logoIPFSHash = _ipfsHashForLogo;
        appId = _appId;

        // de initializer must be the app funding manager contract
        _appFundingManagerAddress = msg.sender;

        // the contract should start paused to avoid claims
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice allows an investor to convert the synthetic and range tokens in app tokens
     */
    function claim() external {
        // solhint-disable-next-line
        require(appTokenLaunchingDate <= block.timestamp, "Launching date not reached yet");
        uint256 balanceAdded = AppFundingManager(_appFundingManagerAddress).convertTokens(appId, msg.sender);
        emit ClaimTokens(msg.sender, balanceAdded);
    }

    function name() public view virtual override returns (string memory) {
        return _proxiedName;
    }

    function symbol() public view virtual override returns (string memory) {
        return _proxiedSymbol;
    }

    /**
     * @notice allows app funding manager to mint tokens
     */
    function mint(address to, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(to, amount);
    }
}
