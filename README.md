# Dip-Buyer — an autonomous paper-trading bot

Buys short-term dips in strong stocks, sells the bounce a few days later.
Runs itself in the cloud on GitHub Actions (free) — your laptop can stay closed.

> ⚠️ **PAPER TRADING ONLY.** Educational/research project. Not validated with real money.
> Backtests are hypotheses, not predictions. **Nothing here is financial advice.**

**➡️ Setup instructions: [SETUP.md](SETUP.md)**

---

## The strategy in one paragraph

Once a day at 3:25pm ET, check ~13 liquid high-volatility stocks. Buy one if **(a)** it has dipped
hard (cumulative RSI(2) below 35), **(b)** it's still in a long-term uptrend (above its 200-day
moving average), and **(c)** it doesn't report earnings within 8 days. Max 3 positions, cash only,
no margin. Each buy immediately gets a **−12% stop placed at the broker**, so positions stay
protected even with the computer off. Sell when RSI(2) rises above 65 (the bounce happened) or
after 10 trading days.

Most days it does nothing. That is the design, not a bug.

### Backtest (5 years, ~857 trades)
| Metric | Value |
|---|---|
| Win rate | ~72% |
| Avg per trade | ~+1.25% |
| Worst trade | −12% (stop-capped) |

**Read this caveat:** the stock list was chosen partly *because* those names backtested well, so
these numbers are optimistic (selection bias). Expect worse live. Realistic ceiling if the edge
holds is roughly **15–20% per year** — not per day.

---

## Why it does NOT day-trade

We tested it properly: **83,638 simulated day trades** across 65 stocks over 5 years.

| Morning strategy | Win rate | Profit/trade |
|---|---|---|
| Buy any stock at open, sell at close | 51.2% | +0.046% |
| Buy stocks that gapped up >1% | 50.9% | −0.0003% |
| Buy strong 5-day momentum | 50.9% | +0.050% |
| **Our dip-swing (hold 1–10 days)** | **68.9%** | **+0.441%** |

Every intraday filter lands on ~51% — a coin flip. And the tiny edge that exists (~0.05%) is
**smaller than trading costs (~0.10%)**, so after spread/slippage day trading is reliably negative.
Holding a few days is where the edge actually is.

---

## Things we tested that made it WORSE

All backtested on 5 years. Please don't re-add them without new evidence:

| Idea | Result |
|---|---|
| Trailing stops | 3% trail drops win rate 72% → 52%. Exits right before the bounce |
| Profit targets (+3%) | Profit/trade 1.17% → 0.42%. Caps winners, not losers |
| Scanning 65+ stocks | Profit/trade halves; 19 of 65 names were net losers |
| Market-breadth filter | Win rate unchanged at every setting; deletes profitable trades |
| Volatility/VIX filter | +10% avg but −55% trades → less total profit |
| Picking the "best" signal first | Deepest-dip-first is *worse* than plain list order |

**The pattern: filters that remove trades usually remove profitable ones.** A better average on far
fewer trades is worse, not better.

## Infrastructure bugs that cost real money

- Multiple bots left enabled at once → rogue trades in the wrong symbols
- A stop order that silently failed → an unprotected position across a 4-day weekend
- Two schedulers firing at once → 5 orders instead of 3, bought on margin
- Late cron runs → orders queued to the next open, exposed to overnight gaps

**Always verify the protective stop actually exists after a buy. Never assume an order succeeded.**
GitHub's built-in cron is unreliable — use an external trigger (see SETUP.md).

---

## Files

| File | Purpose |
|---|---|
| `dip_trader.ps1` | The bot |
| `earnings_calendar.py` | Free earnings dates (yfinance) → `earnings.json` |
| `dashboard.py` + `START_DASHBOARD.bat` | Local dashboard (positions, signals, charts, news) |
| `.github/workflows/dip-trader.yml` | Cloud schedule |
| `*_test.ps1` | The backtests behind every claim above — run them yourself |

Older files (`trader.ps1`, `screener.ps1`, `intc_vwap.ps1`, and the disabled workflows) are the
previous **momentum** bot. It was tested, lost money, and was replaced. Kept for reference only —
**do not enable them.**
