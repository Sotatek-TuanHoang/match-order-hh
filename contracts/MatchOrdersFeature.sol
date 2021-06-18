/*

  Copybuy 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/
pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "./libs/LibRichErrors.sol";
import "./libs/LibExchangeRichErrors.sol";
import "./libs/LibNativeOrder.sol";
import "./libs/LibSignature.sol";
import "./native_orders/NativeOrdersInfo.sol";
import "./libs/LibMathV06.sol";
import "./libs/FixinTokenSpender.sol";
import "./libs/FixinCommon.sol";
import "./libs/LibMigrate.sol";
import "./libs/LibBytesV06.sol";
import "./libs/LibSafeMathV06.sol";
import "./libs/IERC20TokenV06.sol";
import "./libs/IMatchOrdersFeature.sol";
import "./libs/IFeature.sol";

contract MatchOrdersFeature is
    IFeature,
    IMatchOrdersFeature,
    FixinCommon,
    FixinTokenSpender,
    NativeOrdersInfo
{
    using LibBytesV06 for bytes;
    using LibSafeMathV06 for uint256;
    using LibSafeMathV06 for uint128;

    string public constant override FEATURE_NAME = "MatchOrders";
    /// @dev Version of this feature.
    uint256 public immutable override FEATURE_VERSION = _encodeVersion(1, 1, 1);


    constructor(address zeroExAddress)
        public
        FixinCommon()
        NativeOrdersInfo(zeroExAddress)
    {
        // solhint-disable-next-line no-empty-blocks
    }

    function testMatch() external override pure returns (uint256 haha) {
        return haha = 1;
    }

    function matchOrders(
        LibNativeOrder.LimitOrder calldata sellOrder,
        LibNativeOrder.LimitOrder calldata buyOrder,
        LibSignature.Signature calldata sellSignature,
        LibSignature.Signature calldata buySignature
    )
        external
        override
        payable
        // refundFinalBalanceNoReentry
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        return _matchOrders(
            sellOrder,
            buyOrder,
            sellSignature,
            buySignature
        );
    }
    /// @dev Validates context for matchOrders. Succeeds or throws.
    /// @param sellOrder First order to match.
    /// @param buyOrder Second order to match.
    /// @param sellOrderHash First matched order hash.
    /// @param buyOrderHash Second matched order hash.
    function _assertValidMatch(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        bytes32 sellOrderHash,
        bytes32 buyOrderHash
    )
        internal
        pure
    {
        // Make sure there is a profitable spread.
        // There is a profitable spread iff the cost per unit bought (OrderA.MakerAmount/OrderA.TakerAmount) for each order is greater
        // than the profit per unit sold of the matched order (OrderB.TakerAmount/OrderB.MakerAmount).
        // This is satisfied by the equations below:
        // <sellOrder.makerAssetAmount> / <sellOrder.takerAssetAmount> >= <buyOrder.takerAssetAmount> / <buyOrder.makerAssetAmount>
        // AND
        // <buyOrder.makerAssetAmount> / <buyOrder.takerAssetAmount> >= <sellOrder.takerAssetAmount> / <sellOrder.makerAssetAmount>
        // These equations can be combined to get the following:
        if (sellOrder.makerAmount.safeMul128(buyOrder.makerAmount) <
            sellOrder.takerAmount.safeMul128(buyOrder.takerAmount)) {
            LibRichErrors.rrevert(LibExchangeRichErrors.NegativeSpreadError(
                sellOrderHash,
                buyOrderHash
            ));
        }
    }

    /// @dev Match two complementary orders that have a profitable spread.
    ///      Each order is filled at their respective price point. However, the calculations are
    ///      carried out as though the orders are both being filled at the buy order's price point.
    ///      The profit made by the sell order goes to the taker (who matched the two orders). This
    ///      function is needed to allow for reentrant order matching (used by `batchMatchOrders` and
    ///      `batchMatchOrdersWithMaximalFill`).
    /// @param sellOrder First order to match.
    /// @param buyOrder Second order to match.
    /// @param sellSignature Proof that order was created by the sell maker.
    /// @param buySignature Proof that order was created by the buy maker.
    /// @param shouldMaximallyFillOrders Indicates whether or not the maximal fill matching strategy should be used
    /// @return matchedFillResults Amounts filled and fees paid by maker and taker of matched orders.
    function _matchOrders(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        LibSignature.Signature memory sellSignature,
        LibSignature.Signature memory buySignature,
    )
        private
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // We assume that buyOrder.takerAssetData == sellOrder.makerAssetData and buyOrder.makerAssetData == sellOrder.takerAssetData
        // by pointing these values to the same location in memory. This is cheaper than checking equality.
        // If this assumption isn't true, the match will fail at signature validation.
        buyOrder.makerToken = sellOrder.takerToken;
        buyOrder.takerToken = sellOrder.makerToken;

        // Get sell & buy order info
        LibNativeOrder.OrderInfo memory sellOrderInfo = getOrderInfo(sellOrder);
        LibNativeOrder.OrderInfo memory buyOrderInfo = getOrderInfo(buyOrder);

        // Fetch taker address
        address takerAddress = msg.sender;

        // Either our context is valid or we revert
        _assertFillableOrder(
            sellOrder,
            sellOrderInfo,
            takerAddress,
            sellSignature
        );
        _assertFillableOrder(
            buyOrder,
            buyOrderInfo,
            takerAddress,
            buySignature
        );
        _assertValidMatch(
            sellOrder,
            buyOrder,
            sellOrderInfo.orderHash,
            buyOrderInfo.orderHash
        );

        // Compute proportional fill amounts
        matchedFillResults = calculateMatchedFillResults(
            sellOrder,
            buyOrder,
            sellOrderInfo.takerTokenFilledAmount,
            buyOrderInfo.takerTokenFilledAmount,
        );

        // Update exchange state
        _updateFilledState(
            sellOrder,
            takerAddress,
            sellOrderInfo.orderHash,
            sellOrderInfo.takerTokenFilledAmount,
            sellTakerRemainingAmountAfterMatch
        );
        _updateFilledState(
            buyOrder,
            takerAddress,
            buyOrderInfo.orderHash,
            buyOrderInfo.takerTokenFilledAmount,
            buyTakerRemainingAmountAfterMatch
        );

        // Settle matched orders. Succeeds or throws.
        _settleMatchedOrders(
            sellOrderInfo.orderHash,
            buyOrderInfo.orderHash,
            sellOrder,
            buyOrder,
            takerAddress,
            matchedFillResults
        );

        return matchedFillResults;
    }

    function getOrderInfo(LibNativeOrder.LimitOrder memory order)
    public
    view
    returns (LibNativeOrder.OrderInfo memory orderInfo)
    {
        // Compute the order hash and fetch the amount of takerAsset that has already been filled
        LibNativeOrder.OrderInfo memory orderInfo = getLimitOrderInfo(order);

        // If order.makerAssetAmount is zero, we also reject the order.
        // While the Exchange contract handles them correctly, they create
        // edge cases in the supporting infrastructure because they have
        // an 'infinite' price when computed by a simple division.
        if (order.makerAmount == 0) {
            orderInfo.status = LibNativeOrder.OrderStatus.INVALID;
            return orderInfo;
        }

        // If order.takerAssetAmount is zero, then the order will always
        // be considered filled because 0 == takerAssetAmount == orderTakerAssetFilledAmount
        // Instead of distinguishing between unfilled and filled zero taker
        // amount orders, we choose not to support them.
        if (order.takerAmount == 0) {
            orderInfo.status = LibNativeOrder.OrderStatus.INVALID;
            return orderInfo;
        }

        return orderInfo;
    }


    function _assertFillableOrder(
        LibNativeOrder.LimitOrder memory order,
        LibNativeOrder.OrderInfo memory orderInfo,
        address takerAddress,
        LibSignature.Signature memory signature
    )
    internal
    view
    {
        // An order can only be filled if its status is FILLABLE.
        if (orderInfo.status != LibNativeOrder.OrderStatus.FILLABLE) {
            LibRichErrors.rrevert(LibExchangeRichErrors.OrderStatusError(
                    orderInfo.orderHash,
                        LibNativeOrder.OrderStatus(orderInfo.status)
                ));
        }

        // Validate sender is allowed to fill this order
        if (order.sender != address(0)) {
            if (order.sender != msg.sender) {
                LibRichErrors.rrevert(LibExchangeRichErrors.ExchangeInvalidContextError(
                        LibExchangeRichErrors.ExchangeContextErrorCodes.INVALID_SENDER,
                        orderInfo.orderHash,
                        msg.sender
                    ));
            }
        }

        // Validate taker is allowed to fill this order
        if (order.taker != address(0)) {
            if (order.taker != takerAddress) {
                LibRichErrors.rrevert(LibExchangeRichErrors.ExchangeInvalidContextError(
                        LibExchangeRichErrors.ExchangeContextErrorCodes.INVALID_TAKER,
                        orderInfo.orderHash,
                        takerAddress
                    ));
            }
        }

        // Signature must be valid for the order.
        {
            address signer = LibSignature.getSignerOfHash(
                orderInfo.orderHash,
                signature
            );
            if (signer != order.maker) {
                LibRichErrors.rrevert(LibExchangeRichErrors.SignatureError(
                    LibExchangeRichErrors.SignatureErrorCodes.BAD_ORDER_SIGNATURE,
                    orderInfo.orderHash
                ));
            }
        }
    }

    function calculateMatchedFillResults(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        uint256 sellOrderTakerAssetFilledAmount,
        uint256 buyOrderTakerAssetFilledAmount,
    )
    internal
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // Derive maker asset amounts for sell & buy orders, given store taker assert amounts
        uint256 sellTakerAssetAmountRemaining = sellOrder.takerAmount.safeSub(sellOrderTakerAssetFilledAmount);
        uint256 sellMakerAssetAmountRemaining = LibMathV06.safeGetPartialAmountFloor(
            sellOrder.makerAmount,
            sellOrder.takerAmount,
            sellTakerAssetAmountRemaining
        );
        uint256 buyTakerAssetAmountRemaining = buyOrder.takerAmount.safeSub(buyOrderTakerAssetFilledAmount);
        uint256 buyMakerAssetAmountRemaining = LibMathV06.safeGetPartialAmountFloor(
            buyOrder.makerAmount,
            buyOrder.takerAmount,
            buyTakerAssetAmountRemaining
        );


        matchedFillResults = _calculateMatchedFillResults(
            sellOrder,
            buyOrder,
            sellMakerAssetAmountRemaining,
            sellTakerAssetAmountRemaining,
            buyMakerAssetAmountRemaining,
            buyTakerAssetAmountRemaining
        );
        return matchedFillResults;
    }

    function _calculateMatchedFillResults(
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        uint256 sellMakerAssetAmountRemaining,
        uint256 sellTakerAssetAmountRemaining,
        uint256 buyMakerAssetAmountRemaining,
        uint256 buyTakerAssetAmountRemaining
    )
    private
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        //price final is price of matchedFillResults - which always sell price.
        uint256 priceFinal = sellTakerAssetAmountRemaining.safeDiv(sellMakerAssetAmountRemaining);
        //if seller can sell more than buyer can buy. this final amount will calculate follow: 
        if (sellMakerAssetAmountRemaining > buyTakerAssetAmountRemaining) {
            matchedFillResults.makerAmountFinal = buyTakerAssetAmountRemaining;
            matchedFillResults.takerAmountFinal = priceFinal.safeMul(buyTakerAssetAmountRemaining);
            matchedFillResults.buyTakerRemainingAmountAfterMatch = 0;
            matchedFillResults.buyMakerRemainingAmountAfterMatch = 0;
            matchedFillResults.sellMakerRemainingAmountAfterMatch = sellMakerAssetAmountRemaining.safeSub(buyTakerAssetAmountRemaining);
            matchedFillResults.sellTakerRemainingAmountAfterMatch = priceFinal.safeMul(matchedFillResults.sellMakerRemainingAmountAfterMatch);

        } else {
            matchedFillResults.makerAmountFinal = sellMakerAssetAmountRemaining;
            matchedFillResults.takerAmountFinal = sellTakerAssetAmountRemaining;
            matchedFillResults.sellMakerRemainingAmountAfterMatch = 0;
            matchedFillResults.sellTakerRemainingAmountAfterMatch = 0;
            matchedFillResults.buyTakerRemainingAmountAfterMatch = buyTakerAssetAmountRemaining.safeSub(sellMakerAssetAmountRemaining);
            matchedFillResults.buyMakerRemainingAmountAfterMatch = LibMathV06.safeGetPartialAmountFloor(
                buyMakerAssetAmountRemaining,
                buyTakerAssetAmountRemaining,
                matchedFillResults.buyTakerRemainingAmountAfterMatch
            );
        }

        return matchedFillResults;
    }

    function _calculateCompletebuyFill(
        LibNativeOrder.LimitOrder memory sellOrder,
        uint256 buyMakerAssetAmountRemaining,
        uint256 buyTakerAssetAmountRemaining
    )
    private
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        matchedFillResults.buy.makerAssetFilledAmount = buyMakerAssetAmountRemaining;
        matchedFillResults.buy.takerAssetFilledAmount = buyTakerAssetAmountRemaining;
        matchedFillResults.sell.takerAssetFilledAmount = buyMakerAssetAmountRemaining;
        // Round down to ensure the sell maker's exchange rate does not exceed the price specified by the order.
        // We favor the sell maker when the exchange rate must be rounded and the profit is being paid in the
        // sell maker asset.
        matchedFillResults.sell.makerAssetFilledAmount = LibMathV06.safeGetPartialAmountFloor(
            sellOrder.makerAmount,
            sellOrder.takerAmount,
            buyMakerAssetAmountRemaining
        );

        return matchedFillResults;
    }

    function _calculateCompleteFillBoth(
        uint256 sellMakerAssetAmountRemaining,
        uint256 sellTakerAssetAmountRemaining,
        uint256 buyMakerAssetAmountRemaining,
        uint256 buyTakerAssetAmountRemaining
    )
    private
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // Calculate the fully filled results for both orders.
        matchedFillResults.sell.makerAssetFilledAmount = sellMakerAssetAmountRemaining;
        matchedFillResults.sell.takerAssetFilledAmount = sellTakerAssetAmountRemaining;
        matchedFillResults.buy.makerAssetFilledAmount = buyMakerAssetAmountRemaining;
        matchedFillResults.buy.takerAssetFilledAmount = buyTakerAssetAmountRemaining;

        return matchedFillResults;
    }
    /// @dev Settles matched order by transferring appropriate funds between order makers, taker, and fee recipient.
    /// @param sellOrderHash First matched order hash.
    /// @param buyOrderHash Second matched order hash.
    /// @param sellOrder First matched order.
    /// @param buyOrder Second matched order.
    /// @param takerAddress Address that matched the orders. The taker receives the spread between orders as profit.
    /// @param matchedFillResults Struct holding amounts to transfer between makers, taker, and fee recipients.
    function _settleMatchedOrders(
        bytes32 sellOrderHash,
        bytes32 buyOrderHash,
        LibNativeOrder.LimitOrder memory sellOrder,
        LibNativeOrder.LimitOrder memory buyOrder,
        address takerAddress,
        LibNativeOrder.MatchedFillResults memory matchedFillResults
    )
        private
    {
        address sellMakerAddress = sellOrder.maker;
        address buyMakerAddress = buyOrder.maker;
        address sellFeeRecipientAddress = sellOrder.feeRecipient;
        address buyFeeRecipientAddress = buyOrder.feeRecipient;

        _transferERC20Tokens(
            buyOrder.makerToken,
            buyMakerAddress,
            sellMakerAddress,
            matchedFillResults.makerAmountFinal.safeSub(sellOrder.takerTokenFeeAmount)
        );

        _transferERC20Tokens(
            sellOrder.makerToken,
            sellMakerAddress,
            buyMakerAddress,
            matchedFillResults.takerAmountFinal.safeSub(buyOrder.takerTokenFeeAmount)
        );


        //fee for each order
        _transferERC20Tokens(
            buyOrder.takerToken,
            buyMakerAddress,
            buyFeeRecipientAddress,
            buyOrder.takerTokenFeeAmount
        );

        _transferERC20Tokens(
            sellOrder.takerToken,
            sellMakerAddress,
            sellFeeRecipientAddress,
            sellOrder.takerTokenFeeAmount
        );

        //return change for each side.
        _transferERC20Tokens(
            sellOrder.makerToken,
            sellMakerAddress,
            takerAddress,
            matchedFillResults.profitInsellMakerAsset
        );

        _transferERC20Tokens(
            buyOrder.makerToken,
            buyMakerAddress,
            takerAddress,
            matchedFillResults.profitInbuyMakerAsset
        );

        //todo: pay protocol
        bool didPayProtocolFees = false;

        // Protocol fees are not paid if the protocolFeeCollector contract is not set
        if (!didPayProtocolFees) {
            matchedFillResults.sell.protocolFeePaid = 0;
            matchedFillResults.buy.protocolFeePaid = 0;
        }

        // Settle taker fees.
        if (
            sellFeeRecipientAddress == buyFeeRecipientAddress &&
            sellOrder.takerTokenFeeAmount == buyOrder.takerTokenFeeAmount
        ) {
            // Fee recipients and taker fee assets are identical, so we can
            // transfer them in one go.

            _transferERC20Tokens(
                sellOrder.makerToken,
                takerAddress,
                sellFeeRecipientAddress,
                matchedFillResults.sell.takerFeePaid.safeAdd(matchedFillResults.buy.takerFeePaid)
            );
        } else {
            // buy taker fee -> buy fee recipient

            _transferERC20Tokens(
                sellOrder.makerToken,
                takerAddress,
                sellFeeRecipientAddress,
                matchedFillResults.sell.takerFeePaid
            );


            _transferERC20Tokens(
                buyOrder.takerToken,
                takerAddress,
                buyFeeRecipientAddress,
                matchedFillResults.buy.takerFeePaid
            );
        }
    }

    function _updateFilledState(
        LibNativeOrder.LimitOrder memory order,
        address takerAddress,
        bytes32 orderHash,
        uint256 orderTakerAssetFilledAmount,
        uint256 makerAmountFinal,
        uint256 takerAmountFinal,
        uint256 takerRemainingAmount
    )
    private
    {

        LibNativeOrdersStorage
        .getStorage()
        .orderHashToTakerTokenFilledAmount[orderHash] = takerRemainingAmount;
        // Update state

        emit Fill(
            order.maker,
            order.feeRecipient,
            order.makerToken,
            order.takerToken,
            orderHash,
            takerAddress,
            msg.sender,
            makerAmountFinal,
            takerAmountFinal,
            takerRemainingAmount
        );
    }

    function migrate()
    external
    returns (bytes4 success)
    {
        _registerFeatureFunction(this.matchOrders.selector);
        _registerFeatureFunction(this.testMatch.selector);
        // _registerFeatureFunction(this._assertValidMatch.selector);
        // _registerFeatureFunction(this._matchOrders.selector);
        // _registerFeatureFunction(this.getOrderInfo.selector);
        // _registerFeatureFunction(this._assertFillableOrder.selector);
        // _registerFeatureFunction(this._calculateCompletebuyFill.selector);
        // _registerFeatureFunction(this._calculateCompleteFillBoth.selector);
        // _registerFeatureFunction(this._settleMatchedOrders.selector);
        return LibMigrate.MIGRATE_SUCCESS;
    }
}
