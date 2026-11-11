# Reactive Payday — "Set It and Forget It"

A personal savings automation built on Reactive Network. You point your paycheck at
one address, set one rule, and never touch it again: **every deposit at or above your
threshold is automatically swept into your savings ledger — evaluated on-chain, in
Solidity, with no bot, no cron, no keeper.**

Submitted to the Reactive Omni Buildathon, *"Set It and Forget It"* track.

## The idea in one line

Your wallet should behave like a bank account with a standing order: "any income over
X moves straight to savings." Banks do this with a nightly batch job; Reactive Network
does it with a reactive contract.

## Architecture — three contracts

```
Base Sepolia (84532)                    Reactive Lasna (5318007)              Base Sepolia (84532)
┌──────────────┐   Deposit event        ┌────────────┐   requestCallback()    ┌───────────────┐
│ PaydayVault  │ ─────────────────────▶ │ AutoSaver  │ ─────────────────────▶ │ SavingsLedger │
│ (origin)     │                        │ (reactive) │   via Callback Proxy   │ (destination) │
└──────────────┘                        └────────────┘                        └───────────────┘
```

1. **`PaydayVault`** (origin) — emits `Deposit(address,uint256,uint256)` on every
   incoming transfer. The deposit itself is the trigger; nothing else is scheduled.
2. **`AutoSaver`** (reactive, Lasna) — subscribes to that event topic via the system
   contract in its constructor. For every matching log the system contract calls
   `react()`; the contract applies the owner's rule (amount ≥ `threshold`) and asks the
   system contract to post a callback. Deployer-tunable: `setThreshold()`,
   `setDestination()`.
3. **`SavingsLedger`** (destination) — a plain callback contract (`AbstractCallback`)
   that records the sweep and emits `Swept`. Double-authenticated: only the Base
   Sepolia callback proxy may call it (`onlyServiceProvider`) and only our AutoSaver
   may be the originator (`onlyCallbackSender`).

One rule, one event, one callback — the "if this, then that" runs forever on Reactive
Network. The automation never takes custody of anything: it observes deposits and
records savings, while the vault withdrawal stays with the owner.

## Why this fits the track

- **Set it and forget it literally:** the user's only action is depositing income.
  Every subsequent decision is made by `react()` on Reactive Network.
- **Zero off-chain infrastructure:** no indexer, no cron, no API keys. The trigger is
  an event log; the decision is Solidity; the action is a network-posted callback.
- **Personal, real-world use:** deposit-splitting is one of the few automations an
  ordinary person actually wants.
- **Verification-friendly:** every step of the loop is a public transaction (see below).

## Full-loop proof (tx hashes)

| Step | Chain | Hash |
|---|---|---|
| Deposit trigger (emits `Deposit`) | Base Sepolia | `0x34d4fb51f519120bb50311c42af4f8f158364275ab8c1ae641d5fefe87ddda89` |
| `react()` + callback request | Reactive Lasna | `0x00c22a050e310912f5a1142ecb39e80c4b84fd2b15fe122df963882b796b14be` |
| Callback lands (`Swept`) | Base Sepolia | `0x10f58efc2bd5cc4c26825926ecf85735ef32f21116c092d494ac00c20c604281` |

Addresses, explorer links, and the complete deploy trail: [`deploy/DEPLOYMENTS.md`](deploy/DEPLOYMENTS.md).

Observed latency: **under 10 seconds** from deposit to confirmed callback
(CometBFT ~1 s blocks on Lasna).

## Quickstart

Dependencies are git submodules (`reactive-lib-omni` v0.1.0, `forge-std`) — `forge install` checks them out.

```bash
forge install          # reactive-lib-omni + forge-std
forge test -vv         # local check of the loop (mock system contract)

# live demo, one command — deploys, wires, triggers and waits for the callback
MNEMONIC_PHRASE="..." bash script/demo.sh <threshold_eth> <deposit_eth>
```

`script/demo.sh` reproduces the exact run above: deploys `PaydayVault` + `AutoSaver` +
`SavingsLedger`, funds them, wires the destination, makes the trigger deposit and
polls for the `Swept` callback.

## Video

[`VIDEO_SCRIPT.md`](VIDEO_SCRIPT.md) — under 3 minutes: what it does, the one deposit,
and the three tx hashes landing on reactscan/basescan.
