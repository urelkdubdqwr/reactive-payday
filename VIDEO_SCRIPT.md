# Video Script — Reactive Payday (< 3 minutes, single take, screen + voice)

0:00–0:15 — Hook
"Every month money lands in my wallet and I forget to move the savings part. This is
Reactive Payday: I set one rule — deposits over half a milli-ETH get swept into my
savings ledger — and Reactive Network enforces it forever. No bot, no cron job."

0:15–0:40 — What it is (architecture on the README diagram)
"Three contracts. PaydayVault on Base Sepolia emits one event per deposit. AutoSaver
lives on Reactive Lasna — it subscribed to that event at deploy time, so whenever a
deposit lands, Reactive Network calls its react() function. If the amount passes my
threshold, it requests a callback, and the network posts a transaction back to Base
Sepolia into SavingsLedger — the full event-react-callback loop."

0:40–1:15 — Live: the trigger
(Open PaydayVault on sepolia.basescan.org.) "Here is the only interaction I ever make:
0.001 ETH deposited — tx 34d4fb51… (highlight hash). That deposit IS the automation
trigger. That's the whole user experience."

1:15–1:55 — Live: react + callback
(Open lasna.reactscan.net tx 00c22a05…) "This is AutoSaver's reactive transaction on
Lasna — react() ran, the rule passed, and it asked the system contract for a callback.
Under ten seconds later — (open basescan tx 10f58efc…) — the callback landed: Savings
Ledger recorded the sweep. totalSwept is one milli-ETH, sweep count one. Nobody clicked
anything between the deposit and the callback."

1:55–2:25 — Why it's a good 'forget it' build
"Zero off-chain infrastructure — the trigger is a log, the decision is Solidity, the
action is a network-delivered callback. The automation never holds custody: withdrawals
stay with me. And I can retune it — setThreshold, setDestination — without redeploying."

2:25–2:45 — Close
"Reactive Payday: standing orders for your crypto, built on Reactive Network. Repo and
all transaction hashes are in the README."
