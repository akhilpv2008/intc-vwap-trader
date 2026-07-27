"""Alpaco trading dashboard - your "Bloomberg terminal" view.
Run:  python -m streamlit run dashboard.py
Shows: account P&L, open positions, today's dip signals, earnings blackouts, recent trades.
"""
import os, json, datetime
import requests
import pandas as pd
import streamlit as st

BASE = "https://paper-api.alpaca.markets"
DATA = "https://data.alpaca.markets"

def creds():
    key = os.environ.get("APCA_API_KEY_ID")
    sec = os.environ.get("APCA_API_SECRET_KEY")
    if not key:
        envp = os.path.join(os.path.dirname(__file__), "..", ".env")
        if os.path.exists(envp):
            for line in open(envp):
                if "=" in line:
                    k, v = line.split("=", 1)
                    if k.strip() == "APCA_API_KEY_ID": key = v.strip()
                    if k.strip() == "APCA_API_SECRET_KEY": sec = v.strip()
    return {"APCA-API-KEY-ID": key, "APCA-API-SECRET-KEY": sec}

H = creds()
UNIVERSE = ["NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL","TQQQ"]

st.set_page_config(page_title="Alpaco Trading Desk", layout="wide")
st.title("Alpaco Trading Desk")
st.caption("Dip-buyer strategy - PAPER account. Data live from Alpaca.")

def get(url, base=BASE):
    r = requests.get(base + url, headers=H, timeout=20)
    r.raise_for_status()
    return r.json()

# ---------- account ----------
try:
    acct = get("/v2/account")
    eq = float(acct["equity"]); last = float(acct["last_equity"]); cash = float(acct["cash"])
    day = eq - last; cum = eq - 10000
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Equity", f"${eq:,.2f}")
    c2.metric("Today", f"${day:,.2f}", f"{(day/last*100 if last else 0):.2f}%")
    c3.metric("Since $10k start", f"${cum:,.2f}", f"{cum/100:.2f}%")
    c4.metric("Cash", f"${cash:,.2f}")
except Exception as e:
    st.error(f"Account fetch failed: {e}")

# ---------- positions ----------
st.subheader("Open positions")
try:
    pos = get("/v2/positions")
    if pos:
        df = pd.DataFrame([{
            "Symbol": p["symbol"], "Qty": p["qty"],
            "Entry": f'${float(p["avg_entry_price"]):.2f}',
            "Now": f'${float(p["current_price"]):.2f}',
            "P&L": f'${float(p["unrealized_pl"]):.2f}',
            "P&L %": f'{float(p["unrealized_plpc"])*100:.2f}%',
        } for p in pos])
        st.dataframe(df, use_container_width=True, hide_index=True)
    else:
        st.info("Flat - in cash, waiting for a dip. (Normal ~80% of days.)")
except Exception as e:
    st.error(f"Positions failed: {e}")

# ---------- signals ----------
st.subheader("Today's dip signals")
st.caption("BUY requires: cumulative RSI(2) < 35, price above its 200-day average, and no earnings within 6 days.")

def closes(sym):
    start = (datetime.date.today() - datetime.timedelta(days=420)).isoformat()
    out, tok = [], None
    while True:
        u = f"/v2/stocks/{sym}/bars?timeframe=1Day&start={start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"
        if tok: u += f"&page_token={tok}"
        j = get(u, DATA)
        out += (j.get("bars") or [])
        tok = j.get("next_page_token")
        if not tok: break
    return [b["c"] for b in out]

def rsi(c, p):
    i = len(c) - 1
    g = l = 0.0
    for j in range(i - p + 1, i + 1):
        d = c[j] - c[j-1]
        g += d if d > 0 else 0
        l += -d if d < 0 else 0
    al = l / p
    return 100.0 if al == 0 else 100 - 100 / (1 + (g/p)/al)

earn = {}
ep = os.path.join(os.path.dirname(__file__), "earnings.json")
if os.path.exists(ep):
    earn = json.load(open(ep)).get("earnings", {})

rows = []
prog = st.progress(0.0)
for n, s in enumerate(UNIVERSE):
    try:
        c = closes(s)
        if len(c) < 205: continue
        r_now, r_yes = rsi(c, 2), rsi(c[:-1], 2)
        cum_r = r_now + r_yes
        sma = sum(c[-200:]) / 200
        px = c[-1]
        e = earn.get(s) or {}
        days = e.get("days_away")
        blocked = days is not None and days <= 6
        signal = (cum_r < 35) and (px > sma) and not blocked
        rows.append({
            "Symbol": s, "Price": f"${px:.2f}",
            "cumRSI2": f"{cum_r:.1f}", "Need": "< 35",
            "200-day avg": f"${sma:.2f}",
            "Uptrend": "YES" if px > sma else "no",
            "Earnings": f"{days}d" if days is not None else "-",
            "SIGNAL": "BUY" if signal else ("earnings blackout" if blocked else "wait"),
        })
    except Exception:
        pass
    prog.progress((n+1)/len(UNIVERSE))
prog.empty()

if rows:
    sig = pd.DataFrame(rows)
    st.dataframe(sig, use_container_width=True, hide_index=True)
    buys = [r for r in rows if r["SIGNAL"] == "BUY"]
    if buys:
        st.success(f"{len(buys)} BUY signal(s): " + ", ".join(r["Symbol"] for r in buys))
    else:
        st.info("No dip setups right now - the bot stays in cash.")

# ---------- recent trades ----------
st.subheader("Recent trades")
try:
    since = (datetime.date.today() - datetime.timedelta(days=30)).isoformat()
    orders = get(f"/v2/orders?status=all&limit=100&direction=desc&after={since}T00:00:00Z")
    fills = [o for o in orders if float(o.get("filled_qty") or 0) > 0]
    if fills:
        st.dataframe(pd.DataFrame([{
            "When": (o.get("filled_at") or "")[:16].replace("T", " "),
            "Side": o["side"].upper(), "Qty": o["filled_qty"], "Symbol": o["symbol"],
            "Price": f'${float(o["filled_avg_price"]):.2f}',
        } for o in fills]), use_container_width=True, hide_index=True)
    else:
        st.info("No fills in the last 30 days.")
except Exception as e:
    st.error(f"Orders failed: {e}")

st.caption("Paper account. Strategy backtested but not yet forward-validated - not financial advice.")
