// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./OracleStructs.sol";

/**
 * @title oracle to get the assets price in USD
 * @author Eric Nordelo
 */
contract SPOracle is ChainlinkClient, Initializable {
    int256 private constant DECIMALS = 18;

    uint256 private _s;
    uint256 private _p;

    uint256 private _validationSCounter;
    uint256 private _validationPCounter;

    ScopeTimestamps public scopeTimestamps;

    /// @notice the token to get the price for
    string public token;

    /// @notice the url to get the prices
    string public apiURL = "https://backend-exchange-oracle-prod.privi.store/past?token=";

    /// @notice the chainlink node
    address public chainlinkNode;

    /// @notice the node job id
    bytes32 public jobId;

    /// @notice the fee in LINK
    uint256 public nodeFee;

    /// @notice the address of the LINK token
    address public linkToken;

    address[] private _owners;

    // solhint-disable-next-line
    constructor() {}

    modifier onlyOwner() {
        uint256 count = _owners.length;
        bool isOwner = false;
        for (uint256 i = 0; i < count; i++) {
            if (_owners[i] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "Only owners can modify the oracle");
        _;
    }

    /**
     * @notice initializes minimal proxy clone
     */
    function initialize(
        string memory _token,
        PriceOracleInfo memory _oracleInfo,
        ScopeTimestamps memory _timestamps,
        address[] memory __owners
    ) external initializer {
        _owners = __owners;
        token = _token;
        linkToken = _oracleInfo.linkToken;
        chainlinkNode = _oracleInfo.chainlinkNode;
        jobId = stringToBytes32(_oracleInfo.jobId);
        nodeFee = (_oracleInfo.nodeFee * LINK_DIVISIBILITY) / 1000;

        scopeTimestamps = _timestamps;

        setChainlinkToken(linkToken);
    }

    function setOracleInfo(PriceOracleInfo calldata _oracleInfo) external onlyOwner {
        linkToken = _oracleInfo.linkToken;
        chainlinkNode = _oracleInfo.chainlinkNode;
        jobId = stringToBytes32(_oracleInfo.jobId);
        nodeFee = (_oracleInfo.nodeFee * LINK_DIVISIBILITY) / 1000; // 0.01 LINK

        setChainlinkToken(linkToken);
    }

    function setAPIURL(string calldata _url) external onlyOwner {
        apiURL = _url;
    }

    // solhint-disable-next-line
    function update_S() external returns (bytes32 requestId) {
        // solhint-disable-next-line
        require(block.timestamp > scopeTimestamps.lastGSlabEndingDate, "Can't update S yet");
        require(_s == 0, "S already set");

        _validationSCounter++;

        Chainlink.Request memory request = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill_S.selector
        );

        // set the request params
        Chainlink.add(
            request,
            "get",
            string(
                abi.encodePacked(
                    apiURL,
                    token,
                    "&start=",
                    uint2str(scopeTimestamps.firstGSlabOpeningDate),
                    "&end=",
                    uint2str(scopeTimestamps.lastGSlabEndingDate)
                )
            )
        );
        Chainlink.add(request, "path", "vwap");
        Chainlink.addInt(request, "times", DECIMALS);

        // Send the request
        return sendChainlinkRequestTo(chainlinkNode, request, nodeFee);
    }

    // solhint-disable-next-line
    function update_P() external returns (bytes32 requestId) {
        // solhint-disable-next-line
        require(block.timestamp > scopeTimestamps.maturityDate, "Can't update P yet");
        require(_p == 0, "P already set");

        _validationPCounter++;

        Chainlink.Request memory request = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill_P.selector
        );

        // set the request params
        Chainlink.add(
            request,
            "get",
            string(
                abi.encodePacked(
                    apiURL,
                    token,
                    "&start=",
                    uint2str(scopeTimestamps.lastGSlabEndingDate),
                    "&end=",
                    uint2str(scopeTimestamps.maturityDate)
                )
            )
        );
        Chainlink.add(request, "path", "vwap");
        Chainlink.addInt(request, "times", DECIMALS);

        // Sends the request
        return sendChainlinkRequestTo(chainlinkNode, request, nodeFee);
    }

    /**
     * @dev Receive the response in the form of uint256
     */
    // solhint-disable-next-line
    function fulfill_S(bytes32 _requestId, uint256 __s) public recordChainlinkFulfillment(_requestId) {
        _s = __s;
    }

    /**
     * @dev Receive the response in the form of uint256
     */
    // solhint-disable-next-line
    function fulfill_P(bytes32 _requestId, uint256 __p) public recordChainlinkFulfillment(_requestId) {
        _p = __p;
    }

    /**
     * @dev returns the last S report of the oracle
     */
    // solhint-disable-next-line
    function latest_S() external view returns (uint256) {
        return _s;
    }

    /**
     * @dev returns the last P report of the oracle
     */
    // solhint-disable-next-line
    function latest_P() external view returns (uint256) {
        return _p;
    }

    function getValidationSCounter() external view returns (uint256) {
        return _validationSCounter;
    }

    function getValidationPCounter() external view returns (uint256) {
        return _validationPCounter;
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            result := mload(add(source, 32))
        }
    }

    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
