# INTC VWAP Mean-Reversion Day-Trader

Paper day-trader on **INTC** using a VWAP mean-reversion strategy. Runs in **GitHub Actions** (laptop OFF) plus a 30-second local loop when the laptop is on.

- **Account:** Alpaca paper `PA3T3IPIRNWJ` (SPCX/TSLA account) — separate from the politician copybot.
- **Entry:** rests a **bracket buy near VWAP** (institutions' fair-value support) on a pullback. Skips entry on a *falling-knife* candle (big red bar on heavy volume).
- **Exit (broker-side OCO, durable):** take-profit **+$1.50**; stop-loss below the recent **swing low** (capped to ~$1.75/share risk). Because it's a bracket, the take-profit and stop are linked and auto-cancel each other.
- **Size:** ~$10k (≈ shares = 10000 / entry price).
- **Schedule:** trade every ~5 min market hours; record daily P&L after close into `pnl_history.csv` (committed back) to build a real track record.

Tuning knobs in `intc_vwap.ps1`: `$BUDGET`, `$TARGET`, `$MAX_RISK`, `$STOP_BUF`.
