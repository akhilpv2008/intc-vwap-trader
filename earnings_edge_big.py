"""BIGGER test of the earnings question: does buying a dip right before earnings beat a normal dip-buy?
Expanded to ~60 stocks and the longest history yfinance will give, to get a meaningful sample size.
Also splits results by year so we can see whether it's a real effect or one lucky regime.
"""
import statistics, collections
import yfinance as yf

SYMS = ["AAPL","MSFT","NVDA","AMZN","GOOGL","META","AVGO","TSLA","AMD","INTC","QCOM","TXN","MU",
        "AMAT","LRCX","ADI","CRM","ADBE","ORCL","NOW","INTU","PANW","SNOW","NET","CRWD","DDOG",
        "SHOP","UBER","ABNB","HOOD","PLTR","COIN","PYPL","SOFI","JPM","BAC","GS","MS","V","MA",
        "AXP","WFC","C","UNH","JNJ","LLY","PFE","MRK","ABBV","XOM","CVX","COP","WMT","COST","HD",
        "NKE","SBUX","MCD","DIS","BA","CAT","GE","HON","LMT","TSM","ASML","ARM","SMCI","DELL","WDC"]

def rsi(c, p=2):
    if len(c) <= p: return 50.0
    g = l = 0.0
    for i in range(len(c)-p, len(c)):
        d = c[i] - c[i-1]
        g += d if d > 0 else 0
        l += -d if d < 0 else 0
    al = l/p
    return 100.0 if al == 0 else 100 - 100/(1 + (g/p)/al)

pre_dip = []        # (return, year) buying a dip the day before earnings
normal_dip = []     # (return, year) our normal dip-buy, NOT near earnings
done = 0
for s in SYMS:
    try:
        t = yf.Ticker(s)
        hist = t.history(period="max")
        if hist.empty or len(hist) < 300: continue
        closes = list(hist["Close"]); dates = [d.date() for d in hist.index]
        idx = {d: i for i, d in enumerate(dates)}
        ed = t.get_earnings_dates(limit=80)
        edates = sorted({i.date() for i in ed.index}) if ed is not None else []
        # map: index -> True if earnings happens within the next 8 trading days
        near = set()
        for e in edates:
            for d in dates:
                if d >= e:
                    j = idx[d]
                    for k in range(max(0, j-8), j+1): near.add(k)
                    break
        for i in range(205, len(closes)-1):
            win = closes[:i+1]
            cum = rsi(win, 2) + rsi(win[:-1], 2)
            sma = sum(closes[i-199:i+1]) / 200
            if not (cum < 35 and closes[i] > sma): continue
            # exit: RSI2>=65 or 10 days
            ret = None
            for j in range(i+1, min(i+11, len(closes))):
                if rsi(closes[:j+1], 2) >= 65 or (j-i) >= 10:
                    ret = (closes[j]-closes[i])/closes[i]*100; break
            if ret is None: continue
            (pre_dip if i in near else normal_dip).append((ret, dates[i].year))
        done += 1
    except Exception:
        pass

def rep(name, a):
    if not a:
        print(f"{name:<44} no data"); return
    v = [x[0] for x in a]
    up = sum(1 for x in v if x > 0)
    sd = statistics.pstdev(v) if len(v) > 1 else 0
    se = sd/(len(v)**0.5) if v else 0
    print(f"{name:<44} n={len(v):<6} win {up/len(v)*100:5.1f}%  avg {statistics.mean(v):+7.3f}%  "
          f"±{se:5.3f} (stderr)  worst {min(v):+7.2f}%")

print(f"\nsymbols processed: {done}")
print("\n=== dip-buy: right before earnings vs normal ===")
rep("dip-buy WITHIN 8 days of earnings", pre_dip)
rep("dip-buy NOT near earnings (current bot)", normal_dip)

print("\n=== pre-earnings dip-buys BY YEAR (is it one lucky regime?) ===")
by = collections.defaultdict(list)
for r, y in pre_dip: by[y].append(r)
for y in sorted(by):
    v = by[y]
    if len(v) < 3: continue
    up = sum(1 for x in v if x > 0)
    print(f"  {y}   n={len(v):<5} win {up/len(v)*100:5.1f}%  avg {statistics.mean(v):+7.3f}%")
