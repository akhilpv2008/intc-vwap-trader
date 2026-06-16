# Autonomous VWAP mean-reversion day-trader - TOP 3 picks (~$3.3k each), TRAILING exit.
# Entry: bracket (limit buy + hard stop + far ceiling) = instant protection on fill.
# While holding: ratchet the stop UP ~1% behind price (trailing take-profit; never down).
# Plus $300 daily-loss kill-switch and AUTO-FLATTEN before the close (pure intraday).
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }

$TOTAL_BUDGET=10000.0
$MAX_DAILY_LOSS=300.0
$TRAIL_PCT=0.010      # trail the stop ~1% behind price
$CEIL_PCT=0.04        # far take-profit ceiling (mostly the trailing stop does the exiting)
$INIT_STOP_PCT=0.010  # initial hard stop ~1% below entry (widened to 1.5x ATR)
$FLATTEN_MIN=5

function Stamp($m){ Write-Host ("{0}  {1}" -f (Get-Date -Format 'u'),$m) }
function OpenSells($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h | Where-Object { $_.side -eq "sell" }) }
function OpenBuys($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h | Where-Object { $_.side -eq "buy" }) }
function CancelSells($sym){ foreach($o in (OpenSells $sym)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function CancelAll($sym){ foreach($o in @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function Pos($sym){ try{ Invoke-RestMethod -Uri "$base/v2/positions/$sym" -Headers $h }catch{ $null } }
function PlaceOCO($sym,$qty,$tp,$stop){ $b=@{symbol=$sym;qty="$qty";side="sell";type="limit";time_in_force="gtc";order_class="oco";take_profit=@{limit_price="$tp"};stop_loss=@{stop_price="$stop"}}|ConvertTo-Json -Depth 5; Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null }

$clock=Invoke-RestMethod -Uri "$base/v2/clock" -Headers $h
if(-not $clock.is_open){ Stamp "market closed."; exit 0 }
$pickFile=Join-Path $PSScriptRoot "pick.json"
if(-not (Test-Path $pickFile)){ Stamp "no pick.json."; exit 0 }
$pick=Get-Content $pickFile | ConvertFrom-Json
$today=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
if($pick.date -ne $today){ Stamp "pick stale; waiting."; exit 0 }
$syms=@($pick.picks | ForEach-Object { $_.symbol })
$perBudget=[math]::Round($TOTAL_BUDGET/$syms.Count,2)

# auto-flatten near close
$minsToClose=([datetime]$clock.next_close - [datetime]$clock.timestamp).TotalMinutes
if($minsToClose -le $FLATTEN_MIN){
  foreach($s in $syms){ CancelAll $s; $p=Pos $s; if($p -and [int]$p.qty -gt 0){ $b=@{symbol=$s;qty="$($p.qty)";side="sell";type="market";time_in_force="day"}|ConvertTo-Json; try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null; Stamp "FLATTEN sold $($p.qty) $s" }catch{} } }
  Stamp "end-of-day flatten done."; exit 0
}

$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[double]$acct.equity-[double]$acct.last_equity
$killed = ($dayPL -le -$MAX_DAILY_LOSS)
if($killed){ Stamp "KILL-SWITCH day P&L $([math]::Round($dayPL,2)) - no new entries (existing trails still manage)." }

foreach($s in $syms){
  try{
    $start=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT13:30:00Z")
    $bars=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=$start&limit=80&feed=iex" -Headers $h).bars
    if(-not $bars -or $bars.Count -lt 4){ continue }
    $price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/trades/latest" -Headers $h).trade.p
    $atr5=(($bars[-10..-1]|ForEach-Object{[double]$_.h-[double]$_.l})|Measure-Object -Average).Average
    $cumPV=0.0;$cumV=0.0; foreach($b in $bars){ $tp=([double]$b.h+[double]$b.l+[double]$b.c)/3; $cumPV+=$tp*[double]$b.v; $cumV+=[double]$b.v }
    $vwap=[math]::Round($cumPV/$cumV,2)
    $p=Pos $s; $qty= if($p){ [int]$p.qty } else { 0 }

    if($qty -gt 0){
      # TRAILING: ratchet stop up ~1% (or 1.5xATR) behind price; never lower it
      $entry=[double]$p.avg_entry_price
      $trail=[math]::Max($TRAIL_PCT*$price, 1.5*$atr5)
      $floor=[math]::Round($entry - [math]::Max($INIT_STOP_PCT*$entry,1.5*$atr5),2)
      $desired=[math]::Round([math]::Max($price-$trail,$floor),2)
      $ceil=[math]::Round($entry*(1+$CEIL_PCT),2)
      $sells=OpenSells $s
      $curStop=0; foreach($o in $sells){ if($o.type -eq "stop" -or $o.stop_price){ $curStop=[double]$o.stop_price } }
      if($sells.Count -eq 0){ try{ PlaceOCO $s $qty $ceil $floor; Stamp "$s protect: OCO stop $floor ceil $ceil" }catch{ Stamp "$s oco err $($_.ErrorDetails.Message)" } }
      elseif($desired -gt $curStop + 0.02){ CancelSells $s; try{ PlaceOCO $s $qty $ceil $desired; Stamp "$s TRAIL stop $curStop -> $desired (price $price)" }catch{ Stamp "$s trail err $($_.ErrorDetails.Message)" } }
      else{ Stamp "$s holding $qty, stop $curStop (price $price)" }
      continue
    }

    if($killed){ continue }
    $existing=OpenBuys $s
    $lb=$bars[-1]; $lbRed=([double]$lb.c -lt [double]$lb.o); $lbBody=[math]::Abs([double]$lb.o-[double]$lb.c)
    $avgBody=(($bars[-10..-1]|ForEach-Object{[math]::Abs([double]$_.o-[double]$_.c)})|Measure-Object -Average).Average
    $avgVol=(($bars[-10..-1]|ForEach-Object{[double]$_.v})|Measure-Object -Average).Average
    $fk=($lbRed -and $lbBody -gt 1.3*$avgBody -and [double]$lb.v -gt 1.3*$avgVol)
    if($fk){ if($existing.Count){ CancelAll $s }; Stamp "$s falling-knife skip"; continue }
    if($existing.Count -ge 1){ Stamp "$s buy resting @ $($existing[0].limit_price)"; continue }
    $entry=[math]::Round([math]::Min($vwap,$price-0.03),2)
    $lot=[int][math]::Floor($perBudget/$entry); if($lot -lt 1){ continue }
    $stopDist=[math]::Max($INIT_STOP_PCT*$entry,1.5*$atr5)
    $tp=[math]::Round($entry*(1+$CEIL_PCT),2); $stopP=[math]::Round($entry-$stopDist,2)
    $body=@{symbol=$s;qty="$lot";side="buy";type="limit";time_in_force="day";limit_price="$entry";order_class="bracket";take_profit=@{limit_price="$tp"};stop_loss=@{stop_price="$stopP"}}|ConvertTo-Json -Depth 5
    try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $body -ContentType "application/json"|Out-Null; Stamp "$s BRACKET buy $lot @ $entry stop $stopP (trailing after fill)" }catch{ Stamp "$s order err $($_.ErrorDetails.Message)" }
  }catch{ Stamp "$s err $($_.Exception.Message)" }
}
