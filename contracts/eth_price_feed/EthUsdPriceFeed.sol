// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// Import the UsingWitnet library that enables interacting with Witnet
import "witnet-ethereum-bridge/contracts/UsingWitnet.sol";
// Import the ERC2362 interface
import "adomedianizer/contracts/IERC2362.sol";
// Import the ethPrice request that you created before
import "../requests/EthPrice.sol";

// Your contract needs to inherit from UsingWitnet
contract EthUsdPriceFeed is UsingWitnet, IERC2362 {

  // The public eth price point
  uint64 public lastPrice;

  // Stores the ID of the last Witnet request
  uint256 public lastRequestId;

  // Stores the timestamp of the last time the public price point was updated
  uint256 public timestamp;

  // Tells if an update has been requested but not yet completed
  bool public pending;

  // The Witnet request object, is set in the constructor
  Request public request;

  // Emits when the price is updated
  event PriceUpdated(uint64);

  // Emits when found an error decoding request result
  event ResultError(string);

  // This is the ERC2362 identifier for a eth price feed, computed as `keccak256("Price-ETH/USD-3")`
  bytes32 constant public ETHUSD3ID = bytes32(hex"dfaa6f747f0f012e8f2069d6ecacff25f5cdf0258702051747439949737fc0b5");

  // This constructor does a nifty trick to tell the `UsingWitnet` library where
  // to find the Witnet contracts on whatever Ethereum network you use.
  constructor (address _wrb) public UsingWitnet(_wrb) {
    // Instantiate the Witnet request
    request = new EthPriceRequest();
  }

  /**
  * @notice Sends `request` to the WitnetRequestsBoard.
  * @dev This method will only succeed if `pending` is 0.
  **/
  function requestUpdate(uint256 _witnetRequestReward, uint256 _witnetResultReward, uint256 _witnetBlockReward) public payable {
    require(!pending, "An update is already pending. Complete it first before requesting another update.");

    // Send the request to Witnet and store the ID for later retrieval of the result
    // The `witnetPostRequest` method comes with `UsingWitnet`
    lastRequestId = witnetPostRequest(request, _witnetRequestReward, _witnetResultReward, _witnetBlockReward);

    // Signal that there is already a pending request
    pending = true;
  }

  /**
  * @notice Reads the result, if ready, from the WitnetRequestsBoard.
  * @dev The `witnetRequestAccepted` modifier comes with `UsingWitnet` and allows to
  * protect your methods from being called before the request has been successfully
  * relayed into Witnet.
  **/
  function completeUpdate() public witnetRequestAccepted(lastRequestId) {
    require(pending, "There is no pending update.");

    // Read the result of the Witnet request
    // The `witnetReadResult` method comes with `UsingWitnet`
    Witnet.Result memory result = witnetReadResult(lastRequestId);

    // If the Witnet request succeeded, decode the result and update the price point
    // If it failed, revert the transaction with a pretty-printed error message
    if (result.isOk()) {
      lastPrice = result.asUint64();
      timestamp = block.timestamp;
      emit PriceUpdated(lastPrice);
    } else {
      string memory errorMessage;

      // Try to read the value as an error message, catch error bytes if read fails
      try result.asErrorMessage() returns (Witnet.ErrorCodes errorCode, string memory e) {
        errorMessage = e;
      }
      catch (bytes memory errorBytes){
        errorMessage = string(errorBytes);
      }
      emit ResultError(errorMessage);
    }

    // In any case, set `pending` to false so a new update can be requested
    pending = false;
  }

  /**
  * @notice Exposes the public data point in an ERC2362 compliant way.
  * @dev Returns error `400` if queried for an unknown data point, and `404` if `completeUpdate` has never been called
  * successfully before.
  **/
  function valueFor(bytes32 _id) external view override returns(int256, uint256, uint256) {
    // Unsupported data point ID
    if(_id != ETHUSD3ID) return(0, 0, 400);
    // No value is yet available for the queried data point ID
    if (timestamp == 0) return(0, 0, 404);

    int256 value = int256(lastPrice);

    return(value, timestamp, 200);
  }
}