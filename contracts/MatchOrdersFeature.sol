/*

  Copyright 2019 ZeroEx Intl.

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

    event Fill(
        address indexed makerAddress,         // Address that created the order.
        address indexed feeRecipientAddress,  // Address that received fees.
        IERC20TokenV06 makerToken,                 // Encoded data specific to makerAsset.
        IERC20TokenV06 takerToken,                 // Encoded data specific to takerAsset.
        bytes32 indexed orderHash,            // EIP712 hash of order (see LibOrder.getTypedDataHash).
        address takerAddress,                 // Address that filled the order.
        address senderAddress,                // Address that called the Exchange contract (msg.sender).
        uint256 makerAssetFilledAmount,       // Amount of makerAsset sold by maker and bought by taker.
        uint256 takerAssetFilledAmount,       // Amount of takerAsset sold by taker and bought by maker.
        uint256 makerFeePaid,                 // Amount of makerFeeAssetData paid to feeRecipient by maker.
        uint256 takerFeePaid,                 // Amount of takerFeeAssetData paid to feeRecipient by taker.
        uint256 protocolFeePaid               // Amount of eth or weth paid to the staking contract.
    );

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
        LibNativeOrder.LimitOrder calldata leftOrder,
        LibNativeOrder.LimitOrder calldata rightOrder,
        LibSignature.Signature calldata leftSignature,
        LibSignature.Signature calldata rightSignature
    )
        external
        override
        payable
        // refundFinalBalanceNoReentry
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        return _matchOrders(
            leftOrder,
            rightOrder,
            leftSignature,
            rightSignature,
            false
        );
    }
    /// @dev Validates context for matchOrders. Succeeds or throws.
    /// @param leftOrder First order to match.
    /// @param rightOrder Second order to match.
    /// @param leftOrderHash First matched order hash.
    /// @param rightOrderHash Second matched order hash.
    function _assertValidMatch(
        LibNativeOrder.LimitOrder memory leftOrder,
        LibNativeOrder.LimitOrder memory rightOrder,
        bytes32 leftOrderHash,
        bytes32 rightOrderHash
    )
        internal
        pure
    {
        // Make sure there is a profitable spread.
        // There is a profitable spread iff the cost per unit bought (OrderA.MakerAmount/OrderA.TakerAmount) for each order is greater
        // than the profit per unit sold of the matched order (OrderB.TakerAmount/OrderB.MakerAmount).
        // This is satisfied by the equations below:
        // <leftOrder.makerAssetAmount> / <leftOrder.takerAssetAmount> >= <rightOrder.takerAssetAmount> / <rightOrder.makerAssetAmount>
        // AND
        // <rightOrder.makerAssetAmount> / <rightOrder.takerAssetAmount> >= <leftOrder.takerAssetAmount> / <leftOrder.makerAssetAmount>
        // These equations can be combined to get the following:
        if (leftOrder.makerAmount.safeMul128(rightOrder.makerAmount) <
            leftOrder.takerAmount.safeMul128(rightOrder.takerAmount)) {
            LibRichErrors.rrevert(LibExchangeRichErrors.NegativeSpreadError(
                leftOrderHash,
                rightOrderHash
            ));
        }
    }

    /// @dev Match two complementary orders that have a profitable spread.
    ///      Each order is filled at their respective price point. However, the calculations are
    ///      carried out as though the orders are both being filled at the right order's price point.
    ///      The profit made by the left order goes to the taker (who matched the two orders). This
    ///      function is needed to allow for reentrant order matching (used by `batchMatchOrders` and
    ///      `batchMatchOrdersWithMaximalFill`).
    /// @param leftOrder First order to match.
    /// @param rightOrder Second order to match.
    /// @param leftSignature Proof that order was created by the left maker.
    /// @param rightSignature Proof that order was created by the right maker.
    /// @param shouldMaximallyFillOrders Indicates whether or not the maximal fill matching strategy should be used
    /// @return matchedFillResults Amounts filled and fees paid by maker and taker of matched orders.
    function _matchOrders(
        LibNativeOrder.LimitOrder memory leftOrder,
        LibNativeOrder.LimitOrder memory rightOrder,
        LibSignature.Signature memory leftSignature,
        LibSignature.Signature memory rightSignature,
        bool shouldMaximallyFillOrders
    )
        internal
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // We assume that rightOrder.takerAssetData == leftOrder.makerAssetData and rightOrder.makerAssetData == leftOrder.takerAssetData
        // by pointing these values to the same location in memory. This is cheaper than checking equality.
        // If this assumption isn't true, the match will fail at signature validation.
        rightOrder.makerToken = leftOrder.takerToken;
        rightOrder.takerToken = leftOrder.makerToken;

        // Get left & right order info
        LibNativeOrder.OrderInfo memory leftOrderInfo = getOrderInfo(leftOrder);
        LibNativeOrder.OrderInfo memory rightOrderInfo = getOrderInfo(rightOrder);

        // Fetch taker address
        address takerAddress = msg.sender;

        // Either our context is valid or we revert
        _assertFillableOrder(
            leftOrder,
            leftOrderInfo,
            takerAddress,
            leftSignature
        );
        _assertFillableOrder(
            rightOrder,
            rightOrderInfo,
            takerAddress,
            rightSignature
        );
        _assertValidMatch(
            leftOrder,
            rightOrder,
            leftOrderInfo.orderHash,
            rightOrderInfo.orderHash
        );

        //todo: change value
        uint protocolFeeMultiplier = 100;

        // Compute proportional fill amounts
        matchedFillResults = calculateMatchedFillResults(
            leftOrder,
            rightOrder,
            leftOrderInfo.takerTokenFilledAmount,
            rightOrderInfo.takerTokenFilledAmount,
            protocolFeeMultiplier,
            tx.gasprice,
            shouldMaximallyFillOrders
        );

        // Update exchange state
        _updateFilledState(
            leftOrder,
            takerAddress,
            leftOrderInfo.orderHash,
            leftOrderInfo.takerTokenFilledAmount,
            matchedFillResults.left
        );
        _updateFilledState(
            rightOrder,
            takerAddress,
            rightOrderInfo.orderHash,
            rightOrderInfo.takerTokenFilledAmount,
            matchedFillResults.right
        );

        // Settle matched orders. Succeeds or throws.
        _settleMatchedOrders(
            leftOrderInfo.orderHash,
            rightOrderInfo.orderHash,
            leftOrder,
            rightOrder,
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
        LibNativeOrder.LimitOrder memory leftOrder,
        LibNativeOrder.LimitOrder memory rightOrder,
        uint256 leftOrderTakerAssetFilledAmount,
        uint256 rightOrderTakerAssetFilledAmount,
        uint256 protocolFeeMultiplier,
        uint256 gasPrice,
        bool shouldMaximallyFillOrders
    )
    internal
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // Derive maker asset amounts for left & right orders, given store taker assert amounts
        uint256 leftTakerAssetAmountRemaining = leftOrder.takerAmount.safeSub(leftOrderTakerAssetFilledAmount);
        uint256 leftMakerAssetAmountRemaining = LibMathV06.safeGetPartialAmountFloor(
            leftOrder.makerAmount,
            leftOrder.takerAmount,
            leftTakerAssetAmountRemaining
        );
        uint256 rightTakerAssetAmountRemaining = rightOrder.takerAmount.safeSub(rightOrderTakerAssetFilledAmount);
        uint256 rightMakerAssetAmountRemaining = LibMathV06.safeGetPartialAmountFloor(
            rightOrder.makerAmount,
            rightOrder.takerAmount,
            rightTakerAssetAmountRemaining
        );

        // Maximally fill the orders and pay out profits to the matcher in one or both of the maker assets.
        if (shouldMaximallyFillOrders) {
//            matchedFillResults = _calculateMatchedFillResultsWithMaximalFill(
//                leftOrder,
//                rightOrder,
//                leftMakerAssetAmountRemaining,
//                leftTakerAssetAmountRemaining,
//                rightMakerAssetAmountRemaining,
//                rightTakerAssetAmountRemaining
//            );
        } else {
            matchedFillResults = _calculateMatchedFillResults(
                leftOrder,
                rightOrder,
                leftMakerAssetAmountRemaining,
                leftTakerAssetAmountRemaining,
                rightMakerAssetAmountRemaining,
                rightTakerAssetAmountRemaining
            );
        }

        // Compute fees for left order
        matchedFillResults.left.makerFeePaid = LibMathV06.safeGetPartialAmountFloor(
            matchedFillResults.left.makerAssetFilledAmount,
            leftOrder.makerAmount,
            leftOrder.takerTokenFeeAmount
        );
        matchedFillResults.left.takerFeePaid = LibMathV06.safeGetPartialAmountFloor(
            matchedFillResults.left.takerAssetFilledAmount,
            leftOrder.takerAmount,
            leftOrder.takerTokenFeeAmount
        );

        // Compute fees for right order
        matchedFillResults.right.makerFeePaid = LibMathV06.safeGetPartialAmountFloor(
            matchedFillResults.right.makerAssetFilledAmount,
            rightOrder.makerAmount,
            rightOrder.takerTokenFeeAmount
        );
        matchedFillResults.right.takerFeePaid = LibMathV06.safeGetPartialAmountFloor(
            matchedFillResults.right.takerAssetFilledAmount,
            rightOrder.takerAmount,
            rightOrder.takerTokenFeeAmount
        );

        // Compute the protocol fee that should be paid for a single fill. In this
        // case this should be made the protocol fee for both the left and right orders.
        uint256 protocolFee = gasPrice.safeMul(protocolFeeMultiplier);
        matchedFillResults.left.protocolFeePaid = protocolFee;
        matchedFillResults.right.protocolFeePaid = protocolFee;

        // Return fill results
        return matchedFillResults;
    }

    function _calculateMatchedFillResults(
        LibNativeOrder.LimitOrder memory leftOrder,
        LibNativeOrder.LimitOrder memory rightOrder,
        uint256 leftMakerAssetAmountRemaining,
        uint256 leftTakerAssetAmountRemaining,
        uint256 rightMakerAssetAmountRemaining,
        uint256 rightTakerAssetAmountRemaining
    )
    private
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // Calculate fill results for maker and taker assets: at least one order will be fully filled.
        // The maximum amount the left maker can buy is `leftTakerAssetAmountRemaining`
        // The maximum amount the right maker can sell is `rightMakerAssetAmountRemaining`
        // We have two distinct cases for calculating the fill results:
        // Case 1.
        //   If the left maker can buy more than the right maker can sell, then only the right order is fully filled.
        //   If the left maker can buy exactly what the right maker can sell, then both orders are fully filled.
        // Case 2.
        //   If the left maker cannot buy more than the right maker can sell, then only the left order is fully filled.
        // Case 3.
        //   If the left maker can buy exactly as much as the right maker can sell, then both orders are fully filled.
        if (leftTakerAssetAmountRemaining > rightMakerAssetAmountRemaining) {
            // Case 1: Right order is fully filled
            matchedFillResults = _calculateCompleteRightFill(
                leftOrder,
                rightMakerAssetAmountRemaining,
                rightTakerAssetAmountRemaining
            );
        } else if (leftTakerAssetAmountRemaining < rightMakerAssetAmountRemaining) {
            // Case 2: Left order is fully filled
            matchedFillResults.left.makerAssetFilledAmount = leftMakerAssetAmountRemaining;
            matchedFillResults.left.takerAssetFilledAmount = leftTakerAssetAmountRemaining;
            matchedFillResults.right.makerAssetFilledAmount = leftTakerAssetAmountRemaining;
            // Round up to ensure the maker's exchange rate does not exceed the price specified by the order.
            // We favor the maker when the exchange rate must be rounded.
            matchedFillResults.right.takerAssetFilledAmount = LibMathV06.safeGetPartialAmountCeil(
                rightOrder.takerAmount,
                rightOrder.makerAmount,
                leftTakerAssetAmountRemaining // matchedFillResults.right.makerAssetFilledAmount
            );
        } else {
            // leftTakerAssetAmountRemaining == rightMakerAssetAmountRemaining
            // Case 3: Both orders are fully filled. Technically, this could be captured by the above cases, but
            //         this calculation will be more precise since it does not include rounding.
            matchedFillResults = _calculateCompleteFillBoth(
                leftMakerAssetAmountRemaining,
                leftTakerAssetAmountRemaining,
                rightMakerAssetAmountRemaining,
                rightTakerAssetAmountRemaining
            );
        }

        // Calculate amount given to taker
        matchedFillResults.profitInLeftMakerAsset = matchedFillResults.left.makerAssetFilledAmount.safeSub(
            matchedFillResults.right.takerAssetFilledAmount
        );

        return matchedFillResults;
    }

    function _calculateCompleteRightFill(
        LibNativeOrder.LimitOrder memory leftOrder,
        uint256 rightMakerAssetAmountRemaining,
        uint256 rightTakerAssetAmountRemaining
    )
    private
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        matchedFillResults.right.makerAssetFilledAmount = rightMakerAssetAmountRemaining;
        matchedFillResults.right.takerAssetFilledAmount = rightTakerAssetAmountRemaining;
        matchedFillResults.left.takerAssetFilledAmount = rightMakerAssetAmountRemaining;
        // Round down to ensure the left maker's exchange rate does not exceed the price specified by the order.
        // We favor the left maker when the exchange rate must be rounded and the profit is being paid in the
        // left maker asset.
        matchedFillResults.left.makerAssetFilledAmount = LibMathV06.safeGetPartialAmountFloor(
            leftOrder.makerAmount,
            leftOrder.takerAmount,
            rightMakerAssetAmountRemaining
        );

        return matchedFillResults;
    }

    function _calculateCompleteFillBoth(
        uint256 leftMakerAssetAmountRemaining,
        uint256 leftTakerAssetAmountRemaining,
        uint256 rightMakerAssetAmountRemaining,
        uint256 rightTakerAssetAmountRemaining
    )
    private
    pure
    returns (LibNativeOrder.MatchedFillResults memory matchedFillResults)
    {
        // Calculate the fully filled results for both orders.
        matchedFillResults.left.makerAssetFilledAmount = leftMakerAssetAmountRemaining;
        matchedFillResults.left.takerAssetFilledAmount = leftTakerAssetAmountRemaining;
        matchedFillResults.right.makerAssetFilledAmount = rightMakerAssetAmountRemaining;
        matchedFillResults.right.takerAssetFilledAmount = rightTakerAssetAmountRemaining;

        return matchedFillResults;
    }
    /// @dev Settles matched order by transferring appropriate funds between order makers, taker, and fee recipient.
    /// @param leftOrderHash First matched order hash.
    /// @param rightOrderHash Second matched order hash.
    /// @param leftOrder First matched order.
    /// @param rightOrder Second matched order.
    /// @param takerAddress Address that matched the orders. The taker receives the spread between orders as profit.
    /// @param matchedFillResults Struct holding amounts to transfer between makers, taker, and fee recipients.
    function _settleMatchedOrders(
        bytes32 leftOrderHash,
        bytes32 rightOrderHash,
        LibNativeOrder.LimitOrder memory leftOrder,
        LibNativeOrder.LimitOrder memory rightOrder,
        address takerAddress,
        LibNativeOrder.MatchedFillResults memory matchedFillResults
    )
        internal
    {
        address leftMakerAddress = leftOrder.maker;
        address rightMakerAddress = rightOrder.maker;
        address leftFeeRecipientAddress = leftOrder.feeRecipient;
        address rightFeeRecipientAddress = rightOrder.feeRecipient;

        _transferERC20Tokens(
            rightOrder.makerToken,
            rightMakerAddress,
            leftMakerAddress,
            matchedFillResults.left.takerAssetFilledAmount
        );

        _transferERC20Tokens(
            leftOrder.makerToken,
            leftMakerAddress,
            rightMakerAddress,
            matchedFillResults.right.takerAssetFilledAmount
        );

        _transferERC20Tokens(
            rightOrder.makerToken,
            rightMakerAddress,
            rightFeeRecipientAddress,
            matchedFillResults.right.makerFeePaid
        );

        _transferERC20Tokens(
            leftOrder.makerToken,
            leftMakerAddress,
            leftFeeRecipientAddress,
            matchedFillResults.left.makerFeePaid
        );

        _transferERC20Tokens(
            leftOrder.makerToken,
            leftMakerAddress,
            takerAddress,
            matchedFillResults.profitInLeftMakerAsset
        );

        _transferERC20Tokens(
            rightOrder.makerToken,
            rightMakerAddress,
            takerAddress,
            matchedFillResults.profitInRightMakerAsset
        );

        //todo: pay protocol
        bool didPayProtocolFees = false;

        // Pay protocol fees for each maker
//        bool didPayProtocolFees = _payTwoProtocolFees(
//            leftOrderHash,
//            rightOrderHash,
//            matchedFillResults.left.protocolFeePaid,
//            leftMakerAddress,
//            rightMakerAddress,
//            takerAddress
//        );


        // Protocol fees are not paid if the protocolFeeCollector contract is not set
        if (!didPayProtocolFees) {
            matchedFillResults.left.protocolFeePaid = 0;
            matchedFillResults.right.protocolFeePaid = 0;
        }

        // Settle taker fees.
        if (
            leftFeeRecipientAddress == rightFeeRecipientAddress &&
            leftOrder.takerTokenFeeAmount == rightOrder.takerTokenFeeAmount
        ) {
            // Fee recipients and taker fee assets are identical, so we can
            // transfer them in one go.

            _transferERC20Tokens(
                leftOrder.makerToken,
                takerAddress,
                leftFeeRecipientAddress,
                matchedFillResults.left.takerFeePaid.safeAdd(matchedFillResults.right.takerFeePaid)
            );
        } else {
            // Right taker fee -> right fee recipient

            _transferERC20Tokens(
                leftOrder.makerToken,
                takerAddress,
                leftFeeRecipientAddress,
                matchedFillResults.left.takerFeePaid
            );


            _transferERC20Tokens(
                rightOrder.takerToken,
                takerAddress,
                rightFeeRecipientAddress,
                matchedFillResults.right.takerFeePaid
            );
        }
    }

    function _updateFilledState(
        LibNativeOrder.LimitOrder memory order,
        address takerAddress,
        bytes32 orderHash,
        uint256 orderTakerAssetFilledAmount,
        LibNativeOrder.FillResults memory fillResults
    )
    internal
    {

        LibNativeOrdersStorage
        .getStorage()
        .orderHashToTakerTokenFilledAmount[orderHash] =
        // OK to overwrite the whole word because we shouldn't get to this
        // function if the order is cancelled.
        orderTakerAssetFilledAmount.safeAdd(fillResults.takerAssetFilledAmount);
        // Update state

        emit Fill(
            order.maker,
            order.feeRecipient,
            order.makerToken,
            order.takerToken,
            orderHash,
            takerAddress,
            msg.sender,
            fillResults.makerAssetFilledAmount,
            fillResults.takerAssetFilledAmount,
            fillResults.makerFeePaid,
            fillResults.takerFeePaid,
            fillResults.protocolFeePaid
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
        // _registerFeatureFunction(this.calculateMatchedFillResults.selector);
        // _registerFeatureFunction(this._calculateMatchedFillResults.selector);
        // _registerFeatureFunction(this._calculateCompleteRightFill.selector);
        // _registerFeatureFunction(this._calculateCompleteFillBoth.selector);
        // _registerFeatureFunction(this._settleMatchedOrders.selector);
        return LibMigrate.MIGRATE_SUCCESS;
    }
}
