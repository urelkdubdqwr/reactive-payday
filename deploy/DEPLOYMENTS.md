# Live Deployments & Proof of the Full Loop

Date: 2026-11-11 · Deployer: `0xeb27c2E248E17fb4E7F0d9dD7b056FB77c154227`

## Contracts

| Contract | Role | Chain | Address | Explorer |
|---|---|---|---|---|
| PaydayVault | Origin (emits `Deposit`) | Base Sepolia (84532) | `0x7C70707a5a81cc1b7BaCAa12da58D51976a23351` | https://sepolia.basescan.org/address/0x7c70707a5a81cc1b7baca12da58d51976a23351 |
| AutoSaver | Reactive (subscribes, decides, requests callback) | Reactive Lasna (5318007) | `0x3e6aBD4e571F19362564D41014AEefF63b249728` | https://lasna.reactscan.net/address/0x3e6abd4e571f19362564d41014aeeff63b249728 |
| SavingsLedger | Destination (receives callback) | Base Sepolia (84532) | `0xD2cd1F80B7FF499b98550FFEAE79AC64b104589C` | https://sepolia.basescan.org/address/0xd2cd1f80b7ff499b98550ffeae79ac64b104589c |

Source code is verified on Sourcify (chain 84532 / 5318007) and byte-for-byte identical
to `src/` in this repo.

## The full loop — every tx hash

| # | Step | Chain | Tx hash | Block |
|---|---|---|---|---|
| 1 | `AutoSaver` deployed — subscription to `PaydayVault.Deposit` registered in constructor | Lasna | `0x66f5e07921c0fc40afae174bc91c3c15da01627d85ade31cc8174273ba6622e3` | 8073585 |
| 2 | `SavingsLedger` deployed, authorized to AutoSaver | Base Sepolia | `0x15d8c2f74b476ce8caee559d83adcf88a59240d5e808d47f80d94e9cffc2ce52` | 57340213 |
| 3 | `setDestination(84532, SavingsLedger)` — wire the rule | Lasna | `0x9082df9fdc426993aaefaef43ae25a23ce51025fb1fd4358bf4607cc10849aaf` | 8073586 |
| 4 | **Trigger:** `Deposit` emitted by 0.001 ETH deposit into PaydayVault | Base Sepolia | `0x34d4fb51f519120bb50311c42af4f8f158364275ab8c1ae641d5fefe87ddda89` | 57340287 |
| 5 | **React:** `react()` fires on Lasna, emits `SweepRequested`, requests the callback | Lasna | `0x00c22a050e310912f5a1142ecb39e80c4b84fd2b15fe122df963882b796b14be` | 8073589 |
| 6 | **Callback:** `SavingsLedger.sweep()` lands on Base Sepolia, emits `Swept` | Base Sepolia | `0x10f58efc2bd5cc4c26825926ecf85735ef32f21116c092d494ac00c20c604281` | 57340294 |

`PaydayVault` itself was created earlier the same day via the deploy script; its
address (row above) carries the code the loop runs against — the `Deposit` log in step
4 proves the wiring.

## Post-loop state (verified on-chain via `cast call`)

- `SavingsLedger.totalSwept()` = `0.001 ETH` (1e15 wei)
- `SavingsLedger.sweepCount()` = `1`

Deposit (block 57340287) and callback (block 57340294) timestamps differ by **1 second**
— the Reactive leg runs at CometBFT ~1 s blocks; the full loop settled in seconds.

## Superseded first deployment (kept for transparency)

The first AutoSaver (`0x8693B0E75D400492893A8c2e62988C412cA2De1e`, Lasna) was deployed
with `destinationChainId = 5318007` (Lasna's own id) instead of 84532. The reactive side
worked — `react()` fired and emitted `SweepRequested` (tx
`0xcc1b463cebd6c896a007933398852915a4c5a087e312513c022b1d80778cd53d`) — but the
callback was routed to the wrong chain. `destinationChainId` was made owner-settable
(same tx always updates chain + recipient together), and the pair above replaces it.
