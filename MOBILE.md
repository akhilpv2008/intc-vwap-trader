# Managing this trading bot from mobile (claude.ai/code)

The bot runs autonomously in GitHub Actions (cloud) — it trades whether or not any app is open.
To check on it or adjust it from your phone:

1. Phone browser -> **claude.ai/code**, sign in.
2. Connect GitHub (account: **akhilpv2008**), open repo **intc-vwap-trader**.
3. Ask Claude things like:
   - "What's the account status / today's P&L?" (uses Alpaca paper account PA3T3IPIRNWJ)
   - "Show the track record" -> reads `pnl_history.csv`
   - "Run the screener" / "trigger the trader workflow" (GitHub Actions: auto-screener, auto-trader, auto-record)
   - "Tighten the stop %, change the watchlist, adjust RSI/MACD thresholds" -> edits `trader.ps1` / `screener.ps1`

## What it does
- `screener.ps1` -> picks top movers (pool of 10) into `pick.json`, every 30 min
- `trader.ps1` -> scans the pool, holds up to 3, VWAP+RSI+MACD entries, trailing stops, cash-only, flat by close, $300 daily kill-switch, event blackouts (`events.json`)
- `auto_record.ps1` -> appends daily P&L to `pnl_history.csv`

## Rules (do not break)
- Equities only. NO overnight holds (flat by 3:55pm) except a name the USER explicitly approves.
- Macro-event aware: no new entries during FOMC/CPI/jobs blackout windows.
- Paper account only. Account PA3T3IPIRNWJ. Separate from the politician copybot (PA39L2W87E2A) and the TSLA strategy.

## Limits on mobile
- The styled report PNG (`report_builder.ps1`) needs a local desktop browser (Edge) to render; on mobile, read the numbers from `pnl_history.csv` instead.
- Local files under C:\Users\...\alpaco are not reachable from the cloud session — only this repo's contents are.
