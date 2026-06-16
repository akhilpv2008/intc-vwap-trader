# Autonomous VWAP mean-reversion day-trader - trades the TOP 3 picks (pick.json), ~$3.3k each.
# Durable bracket orders, volatility-scaled stop/target, $300 daily-loss kill-switch,
# falling-knife gate, and AUTO-FLATTEN before the close (pure intraday, no overnight risk).
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }

$TOTAL_BUDGET=10000.0
$MAX_DAILY_LOSS=300.0
$TP_PCT=0.012
$SL_PCT=0.009
$FLATTEN_MIN=5           # minutes before close to liquidate everything

function Stamp($m){ Write-Host ("{0}  {1}" -f (Get-Date -Format 'u'),$m) }
function OpenOrders($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h) }
function CancelSym($sym){ foreach($o in (OpenOrders $sym)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function PosQty($sym){ try{ [int](Invoke-RestMethod -Uri "$base/v2/positions/$sym" -Headers $h).qty }catch{ 0 } }

$clock=Invoke-RestMethod -Uri "$base/v2/clock" -Headers $h
if(-not $clock.is_open){ Stamp "market closed."; exit 0 }
$pickFile=Join-Path $PSScriptRoot "pick.json"
if(-not (Test-Path $pickFile)){ Stamp "no pick.json."; exit 0 }
$pick=Get-Content $pickFile | ConvertFrom-Json
$today=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
if($pick.date -ne $today){ Stamp "pick stale ($($pick.date)); waiting for today's screen."; exit 0 }
$syms=@($pick.picks | ForEach-Object { $_.symbol })
$perBudget=[math]::Round($TOTAL_BUDGET/$syms.Count,2)

# --- AUTO-FLATTEN near close: cancel orders + market-sell our picks, no new entries ---
$minsToClose=([datetime]$clock.next_close - [datetime]$clock.timestamp).TotalMinutes
if($minsToClose -le $FLATTEN_MIN){
    foreach($s in $syms){ CancelSym $s; $q=PosQty $s; if($q -gt 0){ $b=@{symbol=$s;qty="$q";side="sell";type="market";time_in_force="day"}|ConvertTo-Json; try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null; Stamp "FLATTEN: sold $q $s before close" }catch{ Stamp "flatten err $s: $($_.ErrorDetails.Message)" } } }
    Stamp "end-of-day flatten complete."; exit 0
}

# --- kill-switch (account-level) ---
$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[double]$acct.equity-[double]$acct.last_equity
if($dayPL -le -$MAX_DAILY_LOSS){ Stamp "KILL-SWITCH day P&L $([math]::Round($dayPL,2)); no new entries."; exit 0 }

foreach($s in $syms){
  try{
    $asset=Invoke-RestMethod -Uri "$base/v2/assets/$s" -Headers $h
    if(-not $asset.tradable){ Stamp "$s not tradable"; continue }
    $start=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT13:30:00Z")
    $bars=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=$start&limit=80&feed=iex" -Headers $h).bars
    if(-not $bars -or $bars.Count -lt 4){ Stamp "$s few bars"; continue }
    $price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/trades/latest" -Headers $h).trade.p
    $cumPV=0.0;$cumV=0.0; foreach($b in $bars){ $tp=([double]$b.h+[double]$b.l+[double]$b.c)/3; $cumPV+=$tp*[double]$b.v; $cumV+=[double]$b.v }
    $vwap=[math]::Round($cumPV/$cumV,2)
    $atr5=(($bars[-10..-1]|ForEach-Object{[double]$_.h-[double]$_.l})|Measure-Object -Average).Average
    $avgVol=(($bars[-10..-1]|ForEach-Object{[double]$_.v})|Measure-Object -Average).Average
    $lb=$bars[-1]; $lbRed=([double]$lb.c -lt [double]$lb.o); $lbBody=[math]::Abs([double]$lb.o-[double]$lb.c)
    $avgBody=(($bars[-10..-1]|ForEach-Object{[math]::Abs([double]$_.o-[double]$_.c)})|Measure-Object -Average).Average
    $fallingKnife=($lbRed -and $lbBody -gt 1.3*$avgBody -and [double]$lb.v -gt 1.3*$avgVol)
    $qty=PosQty $s
    if($qty -gt 0){ Stamp "$s holding $qty - bracket managing"; continue }
    $existing=@(OpenOrders $s | Where-Object { $_.side -eq "buy" })
    if($fallingKnife){ if($existing.Count){ CancelSym $s }; Stamp "$s falling-knife - skip"; continue }
    if($existing.Count -ge 1){ Stamp "$s buy bracket resting @ $($existing[0].limit_price)"; continue }
    $entry=[math]::Round([math]::Min($vwap,$price-0.03),2)
    $lot=[int][math]::Floor($perBudget/$entry)
    if($lot -lt 1){ Stamp "$s lot<1 skip"; continue }
    $stopDist=[math]::Max($SL_PCT*$entry, 1.5*$atr5)
    $tpDist=[math]::Max($TP_PCT*$entry, $stopDist*1.4)
    $tp=[math]::Round($entry+$tpDist,2); $stopP=[math]::Round($entry-$stopDist,2)
    $body=@{ symbol=$s; qty="$lot"; side="buy"; type="limit"; time_in_force="day"; limit_price="$entry"; order_class="bracket"; take_profit=@{limit_price="$tp"}; stop_loss=@{stop_price="$stopP"} } | ConvertTo-Json -Depth 5
    try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $body -ContentType "application/json"|Out-Null; Stamp "$s BRACKET buy $lot @ $entry TP $tp STOP $stopP" }catch{ Stamp "$s order err: $($_.ErrorDetails.Message)" }
  }catch{ Stamp "$s loop err: $($_.Exception.Message)" }
}
