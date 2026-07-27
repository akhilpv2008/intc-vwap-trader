"""Alpaco Trading Terminal - account, market overview, charts, signals, news.
Run:  double-click START_DASHBOARD.bat   (or: python -m streamlit run dashboard.py)
Read-only. It shows what the bot sees; it never places orders.
"""
import os, json, datetime
import requests
import pandas as pd
import streamlit as st

BASE = "https://paper-api.alpaca.markets"
DATA = "https://data.alpaca.markets"
UNIVERSE = ["NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL","TQQQ"]

def creds():
    key = os.environ.get("APCA_API_KEY_ID"); sec = os.environ.get("APCA_API_SECRET_KEY")
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
st.set_page_config(page_title="Alpaco Trading Terminal", layout="wide",
                   initial_sidebar_state="collapsed")

def get(url, base=BASE):
    r = requests.get(base + url, headers=H, timeout=25); r.raise_for_status(); return r.json()

@st.cache_data(ttl=300)
def daily_bars(sym, days=420):
    start = (datetime.date.today() - datetime.timedelta(days=days)).isoformat()
    out, tok = [], None
    while True:
        u = f"/v2/stocks/{sym}/bars?timeframe=1Day&start={start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"
        if tok: u += f"&page_token={tok}"
        j = get(u, DATA); out += (j.get("bars") or []); tok = j.get("next_page_token")
        if not tok: break
    return out

def rsi(c, p):
    i = len(c) - 1; g = l = 0.0
    for j in range(i - p + 1, i + 1):
        d = c[j] - c[j-1]
        g += d if d > 0 else 0; l += -d if d < 0 else 0
    al = l / p
    return 100.0 if al == 0 else 100 - 100/(1 + (g/p)/al)

st.title("Alpaco Trading Terminal")
st.caption("Dip-buyer strategy · PAPER account · live data from Alpaca")
if st.button("Refresh data"):
    st.cache_data.clear(); st.rerun()

# ================= ACCOUNT =================
try:
    a = get("/v2/account")
    eq, last, cash = float(a["equity"]), float(a["last_equity"]), float(a["cash"])
    day, cum = eq - last, eq - 10000
    c = st.columns(4)
    c[0].metric("Equity", f"${eq:,.2f}")
    c[1].metric("Today", f"${day:,.2f}", f"{(day/last*100 if last else 0):.2f}%")
    c[2].metric("Since $10k start", f"${cum:,.2f}", f"{cum/100:.2f}%")
    c[3].metric("Cash available", f"${cash:,.2f}")
except Exception as e:
    st.error(f"Account: {e}")

# ================= MARKET OVERVIEW =================
st.subheader("Market overview")
try:
    cols = st.columns(4)
    for i, (sym, label) in enumerate([("SPY","S&P 500"),("QQQ","Nasdaq 100"),
                                      ("DIA","Dow"),("IWM","Small caps")]):
        b = daily_bars(sym, 30)
        if len(b) >= 2:
            chg = (b[-1]["c"] - b[-2]["c"]) / b[-2]["c"] * 100
            cols[i].metric(label, f'${b[-1]["c"]:,.2f}', f"{chg:+.2f}%")
    clock = get("/v2/clock")
    st.caption(f"Market is **{'OPEN' if clock['is_open'] else 'CLOSED'}** · next open {clock['next_open'][:16].replace('T',' ')}")
except Exception as e:
    st.warning(f"Market overview unavailable: {e}")

# ================= EQUITY CURVE =================
st.subheader("Your account over time")
try:
    ph = get("/v2/account/portfolio/history?period=3M&timeframe=1D")
    eqdf = pd.DataFrame({
        "Date": [datetime.datetime.fromtimestamp(t).date() for t in ph["timestamp"]],
        "Equity": ph["equity"],
    }).set_index("Date")
    eqdf = eqdf[eqdf["Equity"] > 0]
    st.line_chart(eqdf, height=260)
    st.caption("Starting balance was $10,000. Flat stretches = bot in cash waiting for a dip.")
except Exception as e:
    st.warning(f"Equity history unavailable: {e}")

# ================= POSITIONS =================
st.subheader("What we own right now")
try:
    pos = get("/v2/positions")
    if pos:
        st.dataframe(pd.DataFrame([{
            "Stock": p["symbol"], "Shares": p["qty"],
            "Bought at": f'${float(p["avg_entry_price"]):.2f}',
            "Now": f'${float(p["current_price"]):.2f}',
            "Profit/Loss": f'${float(p["unrealized_pl"]):.2f}',
            "%": f'{float(p["unrealized_plpc"])*100:.2f}%',
        } for p in pos]), use_container_width=True, hide_index=True)
    else:
        st.info("Nothing owned - all in cash, waiting for a stock to go on sale. "
                "This is normal about 80% of days.")
except Exception as e:
    st.error(f"Positions: {e}")

# ================= SIGNALS =================
st.subheader("Today's shopping list")
st.caption("To BUY, a stock needs: (1) a sharp dip - cumulative RSI(2) under 35, "
           "(2) still healthy long-term - price above its 200-day average, "
           "(3) no earnings announcement within 6 days.")

earn = {}
ep = os.path.join(os.path.dirname(__file__), "earnings.json")
if os.path.exists(ep):
    try: earn = json.load(open(ep)).get("earnings", {})
    except Exception: pass

rows, chartable = [], {}
bar = st.progress(0.0, text="Checking stocks...")
for n, s in enumerate(UNIVERSE):
    try:
        b = daily_bars(s)
        c = [x["c"] for x in b]
        if len(c) < 205: continue
        cum_r = rsi(c, 2) + rsi(c[:-1], 2)
        sma = sum(c[-200:]) / 200
        px = c[-1]
        days = (earn.get(s) or {}).get("days_away")
        blocked = days is not None and days <= 6
        ok_dip, ok_trend = cum_r < 35, px > sma
        signal = ok_dip and ok_trend and not blocked
        rows.append({
            "Stock": s, "Price": f"${px:.2f}",
            "Dip score": f"{cum_r:.1f}", "On sale? (<35)": "YES" if ok_dip else "no",
            "200-day avg": f"${sma:.2f}", "Healthy?": "YES" if ok_trend else "no",
            "Earnings in": f"{days}d" if days is not None else "-",
            "VERDICT": "BUY" if signal else ("earnings - skip" if blocked else "wait"),
        })
        chartable[s] = b
    except Exception:
        pass
    bar.progress((n+1)/len(UNIVERSE), text=f"Checking {s}...")
bar.empty()

if rows:
    st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)
    buys = [r["Stock"] for r in rows if r["VERDICT"] == "BUY"]
    blocks = [r["Stock"] for r in rows if r["VERDICT"] == "earnings - skip"]
    if buys: st.success(f"BUY signal: {', '.join(buys)} - the bot will act at 3:25pm ET.")
    else:    st.info("No stocks on sale right now. The bot stays in cash.")
    if blocks: st.warning(f"Earnings blackout (too risky this week): {', '.join(blocks)}")

# ================= CHART =================
st.subheader("Chart a stock")
pick = st.selectbox("Pick a stock", list(chartable.keys()) if chartable else UNIVERSE)
try:
    b = chartable.get(pick) or daily_bars(pick)
    c = [x["c"] for x in b]
    dts = [x["t"][:10] for x in b]
    sma200 = [sum(c[max(0,i-199):i+1])/min(i+1,200) for i in range(len(c))]
    n = min(180, len(c))
    st.line_chart(pd.DataFrame({"Price": c[-n:], "200-day average": sma200[-n:]},
                               index=pd.to_datetime(dts[-n:])), height=320)
    st.caption("We only buy when the price (blue) is ABOVE the 200-day average (orange) "
               "- that means the stock is still healthy and the drop is likely temporary.")
except Exception as e:
    st.warning(f"Chart unavailable: {e}")

# ================= NEWS =================
st.subheader("News on our stocks")
try:
    j = requests.get(f"{DATA}/v1beta1/news?symbols={','.join(UNIVERSE[:12])}&limit=25",
                     headers=H, timeout=25).json()
    for item in (j.get("news") or []):
        syms = ", ".join(item.get("symbols", [])[:5])
        when = (item.get("created_at") or "")[:16].replace("T", " ")
        url = item.get("url")
        title = item["headline"]
        st.markdown(f"**[{title}]({url})**" if url else f"**{title}**")
        st.caption(f"{syms} · {item.get('source','')} · {when}")
except Exception as e:
    st.warning(f"News unavailable: {e}")

# ================= TRADES =================
st.subheader("Recent trades (30 days)")
try:
    since = (datetime.date.today() - datetime.timedelta(days=30)).isoformat()
    orders = get(f"/v2/orders?status=all&limit=100&direction=desc&after={since}T00:00:00Z")
    fills = [o for o in orders if float(o.get("filled_qty") or 0) > 0]
    if fills:
        st.dataframe(pd.DataFrame([{
            "When": (o.get("filled_at") or "")[:16].replace("T", " "),
            "Action": "BOUGHT" if o["side"] == "buy" else "SOLD",
            "Shares": o["filled_qty"], "Stock": o["symbol"],
            "Price": f'${float(o["filled_avg_price"]):.2f}',
        } for o in fills]), use_container_width=True, hide_index=True)
    else:
        st.info("No trades in the last 30 days.")
except Exception as e:
    st.error(f"Trades: {e}")

st.divider()
st.caption("Paper trading account - no real money. Strategy is backtested (71.8% win rate over "
           "699 trades) but not yet forward-validated. Not financial advice.")
