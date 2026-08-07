# Dip-Buyer Trading Bot — Setup Guide

An autonomous **paper-trading** bot that buys short-term dips in strong stocks and sells the bounce.
Runs itself in the cloud (free), with your laptop closed.

> **PAPER TRADING ONLY.** This is a learning/research project. It has NOT been validated with real
> money. Backtests are not predictions. Nothing here is financial advice.

---

## What it actually does

Once a day at 3:25pm ET it checks ~13 liquid, high-volatility stocks and asks:

1. **Has it dipped hard?** — cumulative RSI(2) (today + yesterday) is below 35
2. **Is it still healthy?** — price is above its 200-day moving average
3. **Any earnings coming?** — skip if the company reports within 8 days

If all three pass, it buys (max 3 positions, cash only, no margin) and arms a **−12% stop at the broker**
so the position is protected even if your computer is off. It sells when RSI(2) rises above 65
(the bounce happened) or after 10 trading days.

Most days it does nothing. That's the design.

### Backtested results (5 years, ~857 trades)
| Metric | Value |
|---|---|
| Win rate | ~72% |
| Average per trade | ~+1.25% |
| Worst single trade | −12% (capped by the stop) |

**Caveat:** this is a backtest on the stocks that were chosen partly *because* they did well
(selection bias). Live results will be worse. Treat the numbers as a hypothesis, not a promise.

---

## Setup (about 30 minutes)

### 1. Alpaca paper account
1. Sign up free at **alpaca.markets** → switch to **Paper Trading**
2. Go to **API Keys** → **Generate New Key**
3. Save the **Key ID** and **Secret Key** (the secret is shown only once)

### 2. Fork this repo
Click **Fork** on GitHub. Keep it **public** — GitHub Actions minutes are free and unlimited on
public repos, which is what makes the cloud scheduling free.

> ⚠️ **Never commit your API keys.** They go in GitHub Secrets (below), never in a file.

### 3. Add your keys as GitHub Secrets
In *your* fork → **Settings → Secrets and variables → Actions → New repository secret**. Add three:

| Name | Value |
|---|---|
| `APCA_API_KEY_ID` | your Alpaca key ID |
| `APCA_API_SECRET_KEY` | your Alpaca secret |
| `APCA_API_BASE_URL` | `https://paper-api.alpaca.markets` |

### 4. Enable the workflow
**Actions** tab → enable workflows → confirm **dip-trader** is listed and enabled.
Disable everything else — **only one trading driver should ever run at a time.**

### 5. Set up reliable scheduling (IMPORTANT)
**GitHub's built-in cron is unreliable** — in our testing it fired anywhere from 30 to 90 minutes
late, repeatedly *after* the market close, which caused orders to queue overnight and cost real money.
Use **cron-job.org** (free) instead:

1. Create a GitHub **fine-grained personal access token**: your avatar → Settings → Developer settings
   → Fine-grained tokens → your repo only → Permissions → **Actions: Read and write**
2. Sign up at **cron-job.org**, create **two** jobs, both with:
   - **URL:** `https://api.github.com/repos/YOURNAME/YOURREPO/actions/workflows/dip-trader.yml/dispatches`
   - **Method:** POST
   - **Headers:**
     - `Accept: application/vnd.github+json`
     - `Authorization: Bearer YOUR_TOKEN`
     - `X-GitHub-Api-Version: 2022-11-28`
   - **Body:** `{"ref":"master"}`
   - **Timezone:** America/New_York, **Mon–Fri**
3. Job 1 time: **09:31** (safety check — verifies stops, never trades)
   Job 2 time: **15:25** (the actual buy/sell decision)
4. Hit **Run now** on each — you should get **HTTP 204**.

### 6. Optional: the local dashboard
```
pip install streamlit pandas requests yfinance
python -m streamlit run dashboard.py
```
Opens at `http://localhost:8501` — account, positions, live signals, charts, news.
Reads credentials from a local `.env` file (never commit it):
```
APCA_API_KEY_ID=your_key
APCA_API_SECRET_KEY=your_secret
APCA_API_BASE_URL=https://paper-api.alpaca.markets
```

---

## Files

| File | Purpose |
|---|---|
| `dip_trader.ps1` | The bot — entries, exits, stops, cash guard |
| `earnings_calendar.py` | Free earnings dates (yfinance) → `earnings.json` |
| `dashboard.py` | Local Streamlit dashboard |
| `.github/workflows/dip-trader.yml` | Cloud schedule |
| `*_test.ps1` | Backtests (see below) |

---

## Hard-won lessons (please read before "improving" it)

Every one of these was tested on 5 years of data. **All of them lost money.** Test before you trust:

| Idea | Result |
|---|---|
| **Day trading** (buy morning, sell at close) | 83,638 trades tested, ~51% win = coin flip. Edge (0.05%) is *smaller than trading costs* (0.10%) → guaranteed slow bleed |
| **Trailing stops** | 3% trail drops win rate 72% → 52%. They exit right before the bounce you're waiting for. Fine for momentum, fatal for mean-reversion |
| **Profit targets** (+3%) | Cuts profit/trade from 1.17% → 0.42%. Caps winners, leaves losers full size |
| **Scanning the whole market** (65+ stocks) | Profit/trade halves (0.91% → 0.39%); 19 of 65 stocks were net losers |
| **Market breadth filter** | Win rate unchanged at 71.8% at every setting; deletes profitable trades |
| **Volatility/VIX filter** | Raises avg/trade ~10% but cuts trade count 55% → less total profit |
| **Picking the "best" signal first** | Deepest-dip-first is *worse* (+1.36%) than plain list order (+1.42%) |

The pattern: **filters that remove trades usually remove profitable ones.** A higher average with far
fewer trades is worse, not better.

### Infrastructure bugs that cost real money
- Multiple bots running at once (old workflows left enabled) → rogue trades
- A stop order that silently failed to place → an unprotected position over a 4-day weekend
- Two schedulers firing simultaneously → 5 orders instead of 3, bought on margin
- Late crons → orders queued to the next morning, exposed to overnight gaps

**Always verify the protective stop actually exists after a buy.** Never assume an order succeeded.

---

## Honest expectations

- It trades **rarely**. Quiet days are normal.
- It **holds overnight** (1–10 days). That's where the edge lives — every flat-by-close version tested loses.
- Realistic ceiling if the edge holds: roughly **15–20%/year**, not per day.
- Anyone showing you 4-figure daily gains is showing you the winning screenshot, not the losing ones.
- **Stay on paper until you have dozens of live trades.** A handful of good weeks proves nothing.
