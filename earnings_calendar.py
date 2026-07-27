"""Fetch next earnings date for each basket symbol -> earnings.json
Free (yfinance, no API key). The dip trader reads this to avoid buying a stock
that reports earnings while we'd still be holding it (max 5-day hold).
"""
import json, datetime, sys

SYMS = ["NVDA","AMD","INTC","HOOD","PLTR","META","MSFT","AMZN","GOOGL","AAPL","TQQQ","QQQ"]

def main():
    try:
        import yfinance as yf
    except ImportError:
        print("yfinance not installed; writing empty calendar")
        json.dump({"generated": str(datetime.date.today()), "earnings": {}},
                  open("earnings.json", "w"), indent=2)
        return 0

    today = datetime.date.today()
    out = {}
    for s in SYMS:
        try:
            ed = yf.Ticker(s).get_earnings_dates(limit=8)
            if ed is not None and len(ed):
                future = [i.date() for i in ed.index if i.date() >= today]
                if future:
                    d = min(future)
                    out[s] = {"date": str(d), "days_away": (d - today).days}
                    continue
            out[s] = {"date": None, "days_away": None}
        except Exception as e:
            print(f"{s}: {type(e).__name__} {str(e)[:60]}")
            out[s] = {"date": None, "days_away": None}

    json.dump({"generated": str(today), "earnings": out},
              open("earnings.json", "w"), indent=2)
    for s, v in out.items():
        print(f"{s:<6} {v['date']}  ({v['days_away']} days)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
