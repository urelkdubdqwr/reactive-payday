// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractCallback } from "omni/base/AbstractCallback.sol";
import { IPayable } from "omni/interfaces/IPayable.sol";

/// @title SavingsLedger
/// @notice Destination-chain contract. Records every sweep the `AutoSaver`
///         reactive contract delivers through the Reactive callback proxy.
///
/// It is a plain contract: no `react()`, no subscription. It just proves the
/// full event → react → callback loop landed on-chain and keeps a running total
/// of everything the automation moved into savings.
contract SavingsLedger is AbstractCallback {
    /// @notice Emitted for every delivered sweep.
    /// @param reactive The AutoSaver contract that requested the callback.
    /// @param payer    The account whose deposit triggered the sweep.
    /// @param amount   The swept amount (wei).
    /// @param total    Cumulative swept amount (wei).
    event Swept(address indexed reactive, address indexed payer, uint256 amount, uint256 total);

    /// @notice Lifetime swept amount.
    uint256 public totalSwept;
    /// @notice Number of sweeps processed.
    uint256 public sweepCount;

    /// @param callbackProxy_ Callback proxy on this chain (the only legit caller).
    /// @param callbackSender_ The `AutoSaver` contract authorized to drive this.
    /// @dev `payable` so the ledger can be funded; the proxy bills the recipient
    ///      for callback execution.
    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {}

    /// @notice Callback target. The first argument is injected by the network
    ///         with the requesting reactive contract's address.
    function sweep(address reactive_, address payer_, uint256 amount_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        totalSwept += amount_;
        sweepCount += 1;
        emit Swept(reactive_, payer_, amount_, totalSwept);
    }

    /// @notice Settle any outstanding callback debt from the ledger's balance.
    function coverDebt() external {
        _coverDebt();
    }
}
