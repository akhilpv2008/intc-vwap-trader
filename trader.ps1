# Autonomous VWAP mean-reversion day-trader. Trades the symbol chosen by screener.ps1 (pick.json).
# Durable broker-side BRACKET orders (entry + linked take-profit + stop). Volatility-scaled
# target/stop. Daily-loss kill-switch. Stateless: derives state from Alpaca.
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }

$BUDGET=10000.0          # $ per position
$MAX_DAILY_LOSS=300.0    # kill-switch: stop new entries if account down this much today
$TP_PCT=0.012            # take-profit ~1.2% of price
$SL_PCT=0.009            # base stop ~0.9% of price (widened to volatility below)

function Stamp($m){ Write-Host ("{0}  {1}" -f (Get-Date -Format 'u'),$m) }
function OpenOrders($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h) }
function CancelSym($sym){ foreach($o in (OpenOrders $sym)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }

# guards
$clock=Invoke-RestMethod -Uri "$base/v2/clock" -Headers $h
if(-not $clock.is_open){ Stamp "market closed."; exit 0 }
$pickFile=Join-Path $PSScriptRoot "pick.json"
if(-not (Test-Path $pickFile)){ Stamp "no pick.json yet (screener hasn't run)."; exit 0 }
$pick=Get-Content $pickFile | ConvertFrom-Json
$today=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
if($pick.date -ne $today){ Stamp "pick is stale ($($pick.date)); waiting for today's screen."; exit 0 }
$SYM=$pick.symbol
$asset=Invoke-RestMethod -Uri "$base/v2/assets/$SYM" -Headers $h
if(-not $asset.tradable){ Stamp "$SYM not tradable."; exit 0 }

# kill-switch
$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[double]$acct.equity-[double]$acct.last_equity
if($dayPL -le -$MAX_DAILY_LOSS){ Stamp "KILL-SWITCH: day P&L $([math]::Round($dayPL,2)) <= -$MAX_DAILY_LOSS. No new entries."; exit 0 }

# data / research
$start=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT13:30:00Z")
$bars=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$SYM/bars?timeframe=5Min&start=$start&limit=80&feed=iex" -Headers $h).bars
$price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$SYM/trades/latest" -Headers $h).trade.p
if(-not $bars -or $bars.Count -lt 4){ Stamp "$SYM not enough bars yet."; exit 0 }
$cumPV=0.0;$cumV=0.0
foreach($b in $bars){ $tp=([double]$b.h+[double]$b.l+[double]$b.c)/3; $cumPV+=$tp*[double]$b.v; $cumV+=[double]$b.v }
$vwap=[math]::Round($cumPV/$cumV,2)
$atr5=(($bars[-10..-1]|ForEach-Object{[double]$_.h-[double]$_.l})|Measure-Object -Average).Average
$avgVol=(($bars[-10..-1]|ForEach-Object{[double]$_.v})|Measure-Object -Average).Average
$lb=$bars[-1]; $lbRed=([double]$lb.c -lt [double]$lb.o); $lbBody=[math]::Abs([double]$lb.o-[double]$lb.c)
$avgBody=(($bars[-10..-1]|ForEach-Object{[math]::Abs([double]$_.o-[double]$_.c)})|Measure-Object -Average).Average
$fallingKnife=($lbRed -and $lbBody -gt 1.3*$avgBody -and [double]$lb.v -gt 1.3*$avgVol)

try{ $pos=Invoke-RestMethod -Uri "$base/v2/positions/$SYM" -Headers $h; $qty=[int]$pos.qty }catch{ $qty=0 }
Stamp "$SYM price=$price vwap=$vwap atr5=$([math]::Round($atr5,2)) fallingKnife=$fallingKnife dayPL=$([math]::Round($dayPL,2)) pos=$qty"

if($qty -gt 0){ Stamp "holding $qty - bracket managing exit."; exit 0 }

# FLAT: arm bracket buy near VWAP on a pullback (mean-reversion long)
$existing=@(OpenOrders $SYM | Where-Object { $_.side -eq "buy" })
if($fallingKnife){ if($existing.Count){ CancelSym $SYM }; Stamp "falling-knife - standing aside."; exit 0 }
if($existing.Count -ge 1){ Stamp "buy bracket already resting @ $($existing[0].limit_price)."; exit 0 }

$entry=[math]::Round([math]::Min($vwap,$price-0.03),2)
$lot=[int][math]::Floor($BUDGET/$entry)
# volatility-scaled exits: stop = max(SL_PCT*price, 1.5*atr5); target = stop*1.4 (>=TP_PCT*price)
$stopDist=[math]::Max($SL_PCT*$entry, 1.5*$atr5)
$tpDist=[math]::Max($TP_PCT*$entry, $stopDist*1.4)
$tp=[math]::Round($entry+$tpDist,2)
$stopP=[math]::Round($entry-$stopDist,2)
$body=@{ symbol=$SYM; qty="$lot"; side="buy"; type="limit"; time_in_force="day"; limit_price="$entry";
         order_class="bracket"; take_profit=@{limit_price="$tp"}; stop_loss=@{stop_price="$stopP"} } | ConvertTo-Json -Depth 5
try{
  Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $body -ContentType "application/json"|Out-Null
  Stamp "BRACKET buy $lot $SYM @ $entry | TP $tp (+`$$([math]::Round($tpDist*$lot,0))) | STOP $stopP (-`$$([math]::Round($stopDist*$lot,0)))"
}catch{ Stamp "order err: $($_.ErrorDetails.Message)" }
