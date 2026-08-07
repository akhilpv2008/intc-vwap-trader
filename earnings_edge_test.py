"""Do earnings actually help or hurt? Two questions, answered with data:
 1) If you BUY THE DIP right before earnings, what happens? (our blackout blocks this)
 2) Is the direction of an earnings move predictable at all?
Uses yfinance historical earnings dates + prices.
"""
import datetime, statistics
import yfinance as yf

SYMS = ["NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL",
        "AAPL","MSFT","AMZN","TSLA","CRM","ORCL","QCOM","TXN"]

def rsi(c, p=2):
    if len(c) <= p: return 50.0
    g = l = 0.0
    for i in range(len(c)-p, len(c)):
        d = c[i] - c[i-1]
        g += d if d > 0 else 0
        l += -d if d < 0 else 0
    al = l/p
    return 100.0 if al == 0 else 100 - 100/(1 + (g/p)/al)

pre_dip_moves = []     # bought a dip right before earnings -> next-day return
all_earn_moves = []    # every earnings-day move (absolute size + direction)
normal_moves = []      # random non-earnings days, for comparison

for s in SYMS:
    try:
        t = yf.Ticker(s)
        hist = t.history(period="5y")
        if hist.empty: continue
        closes = list(hist["Close"]); dates = [d.date() for d in hist.index]
        idx = {d: i for i, d in enumerate(dates)}
        ed = t.get_earnings_dates(limit=40)
        if ed is None: continue
        edates = sorted({i.date() for i in ed.index})

        for e in edates:
            # find the trading day index at/just before the earnings date
            i = None
            for d in dates:
                if d >= e:
                    i = idx[d]; break
            if i is None or i < 205 or i+1 >= len(closes): continue

            move = (closes[i+1] - closes[i]) / closes[i] * 100
            all_earn_moves.append(move)

            # was it a dip-buy candidate the day before earnings?
            win = closes[:i+1]
            cum = rsi(win, 2) + rsi(win[:-1], 2)
            sma200 = sum(closes[i-199:i+1]) / 200
            if cum < 35 and closes[i] > sma200:
                pre_dip_moves.append(move)

        # baseline: all non-earnings daily moves
        eset = set()
        for e in edates:
            for d in dates:
                if d >= e: eset.add(idx[d]); break
        for i in range(205, len(closes)-1):
            if i not in eset:
                normal_moves.append((closes[i+1]-closes[i])/closes[i]*100)
    except Exception as ex:
        print(f"{s}: {type(ex).__name__}")

def rep(name, a):
    if not a:
        print(f"{name:<46} no data"); return
    up = sum(1 for x in a if x > 0)
    print(f"{name:<46} n={len(a):<6} up {up/len(a)*100:5.1f}%  avg {statistics.mean(a):+7.3f}%  "
          f"avg SIZE {statistics.mean([abs(x) for x in a]):6.2f}%  worst {min(a):+7.2f}%")

print("\n=== 1) Is an earnings move predictable? ===")
rep("ALL earnings-day moves", all_earn_moves)
rep("Normal (non-earnings) days", normal_moves)
print("\n=== 2) Buying a DIP right before earnings (what our blackout blocks) ===")
rep("dip-buy held THROUGH earnings", pre_dip_moves)
