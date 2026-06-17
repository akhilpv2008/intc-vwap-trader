# Autonomous VWAP + RSI + MACD day-trader. Scans a POOL of candidates (pick.json, up to 10)
# every cycle ALL DAY and holds up to 3 at once (~$3.3k each). When a trade exits, the slot
# frees up and it enters the next qualifying stock. Durable bracket + trailing-stop exits,
# $300 daily kill-switch, auto-flatten before the close (pure intraday).
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }

$TOTAL_BUDGET=10000.0
$MAX_POS=3                      # hold at most 3 positions at once
$perBudget=[math]::Round($TOTAL_BUDGET/$MAX_POS,2)
$MAX_DAILY_LOSS=300.0
$TRAIL_PCT=0.010; $CEIL_PCT=0.04; $INIT_STOP_PCT=0.010
$FLATTEN_MIN=5

function Stamp($m){ Write-Host ("{0}  {1}" -f (Get-Date -Format 'u'),$m) }
function OpenSells($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h | Where-Object { $_.side -eq "sell" }) }
function OpenBuys($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h | Where-Object { $_.side -eq "buy" }) }
function CancelSells($sym){ foreach($o in (OpenSells $sym)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function CancelAll($sym){ foreach($o in @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function Pos($sym){ try{ Invoke-RestMethod -Uri "$base/v2/positions/$sym" -Headers $h }catch{ $null } }
function EmaSeries($vals,$period){ $k=2.0/($period+1); $e=$vals[0]; $out=@($e); for($i=1;$i -lt $vals.Count;$i++){ $e=$vals[$i]*$k+$e*(1-$k); $out+=$e }; return $out }
function Rsi($closes,$period=14){ if($closes.Count -le $period){ return 50 } ; $g=0.0;$l=0.0; for($i=$closes.Count-$period;$i -lt $closes.Count;$i++){ $d=$closes[$i]-$closes[$i-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$period; if($al -eq 0){ return 100 }; $rs=($g/$period)/$al; return [math]::Round(100-100/(1+$rs),1) }
function PlaceBracket($sym,$lot,$entry,$tp,$stop){ $b=@{symbol=$sym;qty="$lot";side="buy";type="limit";time_in_force="day";limit_price="$entry";order_class="bracket";take_profit=@{limit_price="$tp"};stop_loss=@{stop_price="$stop"}}|ConvertTo-Json -Depth 5; Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null }
function PlaceOCO($sym,$qty,$tp,$stop){ $b=@{symbol=$sym;qty="$qty";side="sell";type="limit";time_in_force="gtc";order_class="oco";take_profit=@{limit_price="$tp"};stop_loss=@{stop_price="$stop"}}|ConvertTo-Json -Depth 5; Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null }

$clock=Invoke-RestMethod -Uri "$base/v2/clock" -Headers $h
if(-not $clock.is_open){ Stamp "market closed."; exit 0 }
$pickFile=Join-Path $PSScriptRoot "pick.json"
if(-not (Test-Path $pickFile)){ Stamp "no pick.json."; exit 0 }
$pick=Get-Content $pickFile | ConvertFrom-Json
$today=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
if($pick.date -ne $today){ Stamp "pick stale; waiting."; exit 0 }
$syms=@($pick.picks | ForEach-Object { $_.symbol })

# auto-flatten near close
$minsToClose=([datetime]$clock.next_close - [datetime]$clock.timestamp).TotalMinutes
if($minsToClose -le $FLATTEN_MIN){
  foreach($s in $syms){ CancelAll $s; $p=Pos $s; if($p -and [int]$p.qty -gt 0){ $b=@{symbol=$s;qty="$($p.qty)";side="sell";type="market";time_in_force="day"}|ConvertTo-Json; try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null; Stamp "FLATTEN sold $($p.qty) $s" }catch{} } }
  Stamp "end-of-day flatten done."; exit 0
}

$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[double]$acct.equity-[double]$acct.last_equity
$killed=($dayPL -le -$MAX_DAILY_LOSS)
if($killed){ Stamp "KILL-SWITCH day P&L $([math]::Round($dayPL,2)) - no new entries." }

# Pass 1: manage held positions (trailing) + count committed slots + collect candidates
$held=0; $pendingBuys=0; $cands=@()
foreach($s in $syms){
  try{
    $start=(Get-Date).ToUniversalTime().AddDays(-5).ToString("yyyy-MM-ddT00:00:00Z")
    $all=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=$start&limit=600&feed=iex" -Headers $h).bars
    if(-not $all -or $all.Count -lt 40){ Stamp "$s insufficient history"; continue }
    $bars=@($all | Where-Object { $_.t -like "$today*" }); if($bars.Count -lt 4){ Stamp "$s only $($bars.Count) bars today - waiting"; continue }
    $price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/trades/latest" -Headers $h).trade.p
    $atr5=(($bars[-10..-1]|ForEach-Object{[double]$_.h-[double]$_.l})|Measure-Object -Average).Average
    $cumPV=0.0;$cumV=0.0; foreach($b in $bars){ $tp=([double]$b.h+[double]$b.l+[double]$b.c)/3; $cumPV+=$tp*[double]$b.v; $cumV+=[double]$b.v }
    $vwap=[math]::Round($cumPV/$cumV,2)
    $closes=@($all | ForEach-Object { [double]$_.c })
    $rsiNow=Rsi $closes 14; $rsiPrev=Rsi ($closes[0..($closes.Count-2)]) 14
    $e12=EmaSeries $closes 12; $e26=EmaSeries $closes 26
    $macd=@(); for($i=0;$i -lt $closes.Count;$i++){ $macd+=($e12[$i]-$e26[$i]) }; $sig=EmaSeries $macd 9
    $macdNow=$macd[-1]; $sigNow=$sig[-1]
    $p=Pos $s; $qty= if($p){ [int]$p.qty } else { 0 }

    if($qty -gt 0){
      $entry=[double]$p.avg_entry_price
      $trail=[math]::Max($TRAIL_PCT*$price,1.5*$atr5)
      $floor=[math]::Round($entry-[math]::Max($INIT_STOP_PCT*$entry,1.5*$atr5),2)
      $desired=[math]::Round([math]::Max($price-$trail,$floor),2)
      $ceil=[math]::Round($entry*(1+$CEIL_PCT),2)
      $sells=OpenSells $s; $curStop=0; foreach($o in $sells){ if($o.stop_price){ $curStop=[double]$o.stop_price } }
      if($sells.Count -eq 0){ try{ PlaceOCO $s $qty $ceil $floor; Stamp "$s protect OCO stop $floor" }catch{ Stamp "$s oco err $($_.ErrorDetails.Message)" } }
      elseif($desired -gt $curStop+0.02){ CancelSells $s; try{ PlaceOCO $s $qty $ceil $desired; Stamp "$s TRAIL $curStop->$desired (price $price)" }catch{ Stamp "$s trail err $($_.ErrorDetails.Message)" } }
      else{ Stamp "$s HOLD $qty stop $curStop (price $price)" }
      $held++; continue
    }
    if((OpenBuys $s).Count -ge 1){ $pendingBuys++; Stamp "$s buy bracket resting"; continue }

    # candidate evaluation (all 4 signals)
    $lb=$bars[-1]; $lbBull=([double]$lb.c -ge [double]$lb.o); $lbBody=[math]::Abs([double]$lb.o-[double]$lb.c)
    $avgBody=(($bars[-10..-1]|ForEach-Object{[math]::Abs([double]$_.o-[double]$_.c)})|Measure-Object -Average).Average
    $avgVol=(($bars[-10..-1]|ForEach-Object{[double]$_.v})|Measure-Object -Average).Average
    $fk=(-not $lbBull -and $lbBody -gt 1.3*$avgBody -and [double]$lb.v -gt 1.3*$avgVol)
    if($fk){ Stamp "$s falling-knife"; continue }
    if($price -lt $vwap){ Stamp "$s below VWAP ($price<$vwap)"; continue }
    if(-not $lbBull){ Stamp "$s candle bearish"; continue }
    if(-not ($rsiNow -gt 40 -and $rsiNow -lt 72 -and $rsiNow -ge $rsiPrev)){ Stamp "$s RSI $rsiNow no"; continue }
    if(-not ($macdNow -gt $sigNow)){ Stamp "$s MACD<signal"; continue }
    $score=[math]::Round(($price-$vwap)/$vwap*100,2)   # rank by strength above VWAP
    $cands+=[pscustomobject]@{S=$s;Price=$price;Atr=$atr5;Rsi=$rsiNow;Score=$score}
    Stamp "$s CANDIDATE OK (RSI $rsiNow, +$score% vs VWAP)"
  }catch{ Stamp "$s err $($_.Exception.Message)" }
}

# Pass 2: fill free slots with the strongest candidates
$committed=$held+$pendingBuys
$slots=$MAX_POS-$committed
Stamp "slots: held=$held pending=$pendingBuys free=$slots candidates=$($cands.Count)"
if($slots -gt 0 -and -not $killed -and $cands.Count -gt 0){
  foreach($cd in (@($cands | Sort-Object Score -Descending) | Select-Object -First $slots)){
    $entry=[math]::Round($cd.Price-0.03,2); $lot=[int][math]::Floor($perBudget/$entry); if($lot -lt 1){ continue }
    $stopDist=[math]::Max($INIT_STOP_PCT*$entry,1.5*$cd.Atr)
    $tp=[math]::Round($entry*(1+$CEIL_PCT),2); $stopP=[math]::Round($entry-$stopDist,2)
    try{ PlaceBracket $cd.S $lot $entry $tp $stopP; Stamp "$($cd.S) BUY $lot @ $entry stop $stopP (trailing after fill)" }catch{ Stamp "$($cd.S) order err $($_.ErrorDetails.Message)" }
  }
}
