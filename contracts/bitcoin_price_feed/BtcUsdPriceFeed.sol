pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

// Import the UsingWitnet library that enables interacting with Witnet
import "witnet-ethereum-bridge/contracts/UsingWitnet.sol";
// Import the ERC2362 interface
import "adomedianizer/contracts/IERC2362.sol";
// Import the BitcoinPrice request that you created before
import "../requests/BitcoinPrice.sol";

// Your contract needs to inherit from UsingWitnet
contract BtcUsdPriceFeed is UsingWitnet, IERC2362 {
  uint64 public bitcoinPrice; // The public Bitcoin price point
  uint256 public lastRequestId;      // Stores the ID of the last Witnet request
  uint256 public timestamp; // Stores the timestamp of the last time the public price point was updated
  bool public pending;               // Tells if an update has been requested but not yet completed
  Request public request;            // The Witnet request object, is set in the constructor

  // emits when the price is updated
  event priceUpdated(uint64);

  // emits when found an error decoding request result
  event resultError(string);

  // This is `keccak256("Price-BTC/USD-3")`
  bytes32 constant public BTCUSD3ID = bytes32(hex"637b7efb6b620736c247aaa282f3898914c0bef6c12faff0d3fe9d4bea783020");

  // This constructor does a nifty trick to tell the `UsingWitnet` library where
  // to find the Witnet contracts on whatever Ethereum network you use.
  constructor (address _wrb) UsingWitnet(_wrb) public {
    // Instantiate the Witnet request
    request = new BitcoinPriceRequest();
  }

  function requestUpdate() public payable {
    require(!pending, "An update is already pending. Complete it first before requesting another update.");

    // Amount to pay to the bridge node relaying this request from Ethereum to Witnet
    uint256 _witnetRequestReward = 100 szabo;
    // Amount of wei to pay to the bridge node relaying the result from Witnet to Ethereum
    uint256 _witnetResultReward = 100 szabo;

    // Send the request to Witnet and store the ID for later retrieval of the result
    // The `witnetPostRequest` method comes with `UsingWitnet`
    lastRequestId = witnetPostRequest(request, _witnetRequestReward, _witnetResultReward);

    // Signal that there is already a pending request
    pending = true;
  }

  // The `witnetRequestAccepted` modifier comes with `UsingWitnet` and allows to
  // protect your methods from being called before the request has been successfully
  // relayed into Witnet.
  function completeUpdate() public witnetRequestAccepted(lastRequestId) {
    require(pending, "There is no pending update.");

    // Read the result of the Witnet request
    // The `witnetReadResult` method comes with `UsingWitnet`
    Witnet.Result memory result = witnetReadResult(lastRequestId);

    // If the Witnet request succeeded, decode the result and update the price point
    // If it failed, revert the transaction with a pretty-printed error message
    if (result.isOk()) {
      bitcoinPrice = result.asUint64();
      emit priceUpdated(bitcoinPrice);
    } else {
      (, string memory errorMessage) = result.asErrorMessage();
      emit resultError(errorMessage);
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
    if(_id != BTCUSD3ID) return(0, 0, 400);
    // No value is yet available for the queried data point ID
    if (timestamp == 0) return(0, 0, 404);

    int256 value = int256(bitcoinPrice);

    return(value, timestamp, 200);
  }
}
