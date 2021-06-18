// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

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

import "./IERC20TokenV06.sol";
import "./LibSignature.sol";
import "./LibNativeOrder.sol";


/// @dev Feature for interacting with limit orders.
interface IMatchOrdersFeature
{
    event Fill(
        address indexed makerAddress,         // Address that created the order.
        address indexed feeRecipientAddress,  // Address that received fees.
        IERC20TokenV06 makerToken,                 // Encoded data specific to makerAsset.
        IERC20TokenV06 takerToken,                 // Encoded data specific to takerAsset.
        bytes32 indexed orderHash,            // EIP712 hash of order (see LibOrder.getTypedDataHash).
        address takerAddress,                 // Address that filled the order.
        address senderAddress,                // Address that called the Exchange contract (msg.sender).
        uint256 makerAmountFinal,       
        uint256 takerAmountFinal,       
        uint256 remainingAmount 
    );

    function testMatch() external pure returns (uint256 haha);

    function matchOrders(
        LibNativeOrder.LimitOrder calldata leftOrder,
        LibNativeOrder.LimitOrder calldata rightOrder,
        LibSignature.Signature calldata leftSignature,
        LibSignature.Signature calldata rightSignature
    )
        external
        payable
        // refundFinalBalanceNoReentry
        returns (LibNativeOrder.MatchedFillResults memory matchedFillResults);
}
