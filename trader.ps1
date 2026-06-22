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
$DAILY_TARGET=150.0            # lock in the day when total P&L (realized+unrealized) hits this
$TRAIL_PCT=0.010; $CEIL_PCT=0.04; $INIT_STOP_PCT=0.010
$FLATTEN_MIN=5
$etNow=[System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([datetime]::UtcNow,"Eastern Standard Time")
$isFirstHourExit=($etNow.Hour -eq 10 -and $etNow.Minute -ge 30)   # 10:30-10:59 AM ET: take profit on morning holds
$noNewEntries=($etNow.Hour -ge 15)                                   # 3:00 PM ET+: no new entries, let EOD flatten clean up

function Stamp($m){ Write-Host ("{0}  {1}" -f (Get-Date -Format 'u'),$m) }
function OpenSells($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h | Where-Object { $_.side -eq "sell" }) }
function OpenBuys($sym){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h | Where-Object { $_.side -eq "buy" }) }
function CancelSells($sym){ $live="new","held","accepted","partially_filled","pending_new"; foreach($o in @(Invoke-RestMethod -Uri "$base/v2/orders?status=all&symbols=$sym&limit=20&direction=desc" -Headers $h | Where-Object { $_.side -eq "sell" -and $live -contains $_.status })){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function CancelAll($sym){ foreach($o in @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$sym" -Headers $h)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }
function Pos($sym){ try{ Invoke-RestMethod -Uri "$base/v2/positions/$sym" -Headers $h }catch{ $null } }
function EmaSeries($vals,$period){ $k=2.0/($period+1); $e=$vals[0]; $out=@($e); for($i=1;$i -lt $vals.Count;$i++){ $e=$vals[$i]*$k+$e*(1-$k); $out+=$e }; return $out }
function Rsi($closes,$period=14){ if($closes.Count -le $period){ return 50 } ; $g=0.0;$l=0.0; for($i=$closes.Count-$period;$i -lt $closes.Count;$i++){ $d=$closes[$i]-$closes[$i-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$period; if($al -eq 0){ return 100 }; $rs=($g/$period)/$al; return [math]::Round(100-100/(1+$rs),1) }
function PlaceBracket($sym,$lot,$tp,$stop){ $b=@{symbol=$sym;qty="$lot";side="buy";type="market";time_in_force="day";order_class="bracket";take_profit=@{limit_price="$tp"};stop_loss=@{stop_price="$stop"}}|ConvertTo-Json -Depth 5; Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null }
function PlaceOCO($sym,$qty,$tp,$stop){ $b=@{symbol=$sym;qty="$qty";side="sell";type="limit";time_in_force="gtc";order_class="oco";take_profit=@{limit_price="$tp"};stop_loss=@{stop_price="$stop"}}|ConvertTo-Json -Depth 5; Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $b -ContentType "application/json"|Out-Null }

# Returns a named exit signal if candle/indicator analysis says get out now, else $null.
# Patterns sourced from proven TA: shooting star, bearish engulfing, doji reversal,
# VWAP cross, RSI overbought divergence, volume exhaustion.
function CandleExitSignal($bars,$price,$vwap,$rsiNow,$rsiPrev,$protect=$false){
  if($bars.Count -lt 5){ return $null }
  $cb=$bars[-1]; $pb=$bars[-2]; $pb2=$bars[-3]
  $cbBull=[double]$cb.c -gt [double]$cb.o
  $cbO=[double]$cb.o; $cbC=[double]$cb.c; $cbH=[double]$cb.h; $cbL=[double]$cb.l
  $cbBody=[math]::Abs($cbC-$cbO)
  $cbUpperWick=$cbH-[math]::Max($cbO,$cbC)
  $cbVol=[double]$cb.v
  $pbBull=[double]$pb.c -gt [double]$pb.o
  $pbO=[double]$pb.o; $pbC=[double]$pb.c
  $pbBody=[math]::Abs($pbC-$pbO)
  $avgBody=(($bars[-8..-1]|ForEach-Object{[math]::Abs([double]$_.o-[double]$_.c)})|Measure-Object -Average).Average
  $avgVol=(($bars[-8..-1]|ForEach-Object{[double]$_.v})|Measure-Object -Average).Average
  if($avgBody -lt 0.001){ $avgBody=0.001 }

  # 1. SHOOTING STAR: long upper wick (>2x body), tiny body, high volume - classic momentum exhaustion top
  if($cbUpperWick -gt 2.0*[math]::Max($cbBody,0.01) -and $cbBody -lt 0.6*$avgBody -and $cbVol -gt 1.2*$avgVol -and $pbBull){ return "SHOOTING-STAR" }

  # 2. BEARISH ENGULFING: bearish candle fully swallows the prior bullish candle - sellers overwhelmed buyers
  if(-not $cbBull -and $pbBull -and $cbO -gt $pbC -and $cbC -lt $pbO -and $cbBody -gt $pbBody){ return "BEARISH-ENGULFING" }

  # 3. DOJI REVERSAL: near-zero body (indecision) after an uptrend, confirmed by next red candle
  $pbDoji=($pbBody -lt 0.15*$avgBody)
  $pb2Bull=([double]$pb2.c -gt [double]$pb2.o)
  if($pbDoji -and -not $cbBull -and $pb2Bull){ return "DOJI-REVERSAL" }

  # 4. VWAP CROSS BELOW: price fell below VWAP - institutional support gone, trade thesis broken
  if($price -lt $vwap){ return "BELOW-VWAP" }

  # 5. RSI OVERBOUGHT + TURNING DOWN: in protect mode threshold drops to 70 (more sensitive)
  $rsiThresh=if($protect){ 70 }else{ 75 }
  if($rsiNow -gt $rsiThresh -and $rsiNow -lt $rsiPrev){ return "RSI-OVERBOUGHT-TURNING" }

  # 6. VOLUME EXHAUSTION: 3 consecutive declining volumes on up candles - buyers running out of fuel
  if($bars.Count -ge 5){
    $last3=@($bars[-3..-1])
    $allUp=($last3 | Where-Object { [double]$_.c -gt [double]$_.o }).Count -eq 3
    $volFading=([double]$last3[2].v -lt [double]$last3[1].v -and [double]$last3[1].v -lt [double]$last3[0].v)
    $volLow=([double]$last3[2].v -lt 0.55*$avgVol)
    if($allUp -and $volFading -and $volLow){ return "VOLUME-EXHAUSTION" }
  }

  return $null
}

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
  # RELIABLE flatten: cancel ALL open orders account-wide, then close each pick position at market
  try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Delete -Headers $h|Out-Null }catch{}
  Start-Sleep -Seconds 2
  foreach($s in $syms){ $p=Pos $s; if($p -and [int]$p.qty -gt 0){ try{ Invoke-RestMethod -Uri "$base/v2/positions/$s" -Method Delete -Headers $h|Out-Null; Stamp "FLATTEN closed $($p.qty) $s" }catch{ Stamp "flatten err ${s}: $($_.ErrorDetails.Message)" } } }
  Stamp "end-of-day flatten done (cancel-all + close-position)."; exit 0
}

$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[double]$acct.equity-[double]$acct.last_equity
$killed=($dayPL -le -$MAX_DAILY_LOSS)
if($killed){ Stamp "KILL-SWITCH day P&L $([math]::Round($dayPL,2)) - no new entries." }
# PROTECT MODE: day P&L >= $150 - don't flatten, but ride winners with tighter controls + no new entries
$protectMode=($dayPL -ge $DAILY_TARGET)
if($protectMode){ Stamp "PROTECT MODE: day P&L=+$([math]::Round($dayPL,2)) - riding winners, tighter trail (0.5%), no new entries, hair-trigger exits." }
if($protectMode){ $killed=$true }   # block new entries - protect the gain, don't add risk
# EVENT BLACKOUT: no new entries during FOMC/CPI/jobs windows (still manage/flatten held)
$evFile=Join-Path $PSScriptRoot "events.json"
if(Test-Path $evFile){
  $nowU=(Get-Date).ToUniversalTime()
  foreach($e in (Get-Content $evFile|ConvertFrom-Json).events){
    if($nowU -ge [datetime]$e.start -and $nowU -le [datetime]$e.end){ $killed=$true; Stamp "EVENT BLACKOUT: $($e.label) - no new entries until $($e.end)" }
  }
}

# Pass 1: manage held positions (trailing) + count committed slots + collect candidates
$held=0; $pendingBuys=0; $cands=@()
foreach($s in $syms){
  try{
    $start=(Get-Date).ToUniversalTime().AddDays(-5).ToString("yyyy-MM-ddT00:00:00Z")
    $all=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=$start&limit=600&feed=iex" -Headers $h).bars
    if(-not $all -or $all.Count -lt 40){ Stamp "$s insufficient history"; continue }
    $bars=@($all | Where-Object { ([datetime]$_.t).ToUniversalTime().ToString("yyyy-MM-dd") -eq $today }); if($bars.Count -lt 4){ Stamp "$s only $($bars.Count) bars today - waiting"; continue }
    $price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/trades/latest" -Headers $h).trade.p
    $atr5=(($bars[-10..-1]|ForEach-Object{[double]$_.h-[double]$_.l})|Measure-Object -Average).Average
    $cumPV=0.0;$cumV=0.0; foreach($b in $bars){ $tp=([double]$b.h+[double]$b.l+[double]$b.c)/3; $cumPV+=$tp*[double]$b.v; $cumV+=[double]$b.v }
    $vwap=[math]::Round($cumPV/$cumV,2)
    $closes=@($all | ForEach-Object { [double]$_.c })
    $rsiNow=Rsi $closes 14; $rsiPrev=Rsi ($closes[0..($closes.Count-2)]) 14
    $e9=EmaSeries $closes 9; $e21=EmaSeries $closes 21
    $e12=EmaSeries $closes 12; $e26=EmaSeries $closes 26
    $macd=@(); for($i=0;$i -lt $closes.Count;$i++){ $macd+=($e12[$i]-$e26[$i]) }; $sig=EmaSeries $macd 9
    $macdNow=$macd[-1]; $sigNow=$sig[-1]
    $p=Pos $s; $qty= if($p){ [int]$p.qty } else { 0 }

    if($qty -gt 0){
      # candle/indicator exit signals - 6 proven TA patterns checked every cycle
      $exitSig=CandleExitSignal $bars $price $vwap $rsiNow $rsiPrev $protectMode
      if($exitSig -and [double]$p.unrealized_pl -gt 0){
        CancelSells $s; Start-Sleep -Seconds 1
        try{ Invoke-RestMethod -Uri "$base/v2/positions/$s" -Method Delete -Headers $h|Out-Null; Stamp "$s CANDLE-EXIT ($exitSig) profit=+$([math]::Round([double]$p.unrealized_pl,2))" }catch{ Stamp "$s candle-exit err $($_.Exception.Message)" }
        continue
      }
      if($exitSig){ Stamp "$s signal=$exitSig but position not profitable - holding for stop" }
      # first-hour exit: at 10:30 AM ET take profit and free the slot for a fresh afternoon entry
      if($isFirstHourExit -and [double]$p.unrealized_pl -gt 0){
        CancelSells $s; Start-Sleep -Seconds 1
        try{ Invoke-RestMethod -Uri "$base/v2/positions/$s" -Method Delete -Headers $h|Out-Null; Stamp "$s FIRST-HOUR-EXIT profit=+$([math]::Round([double]$p.unrealized_pl,2))" }catch{ Stamp "$s first-hour-exit err $($_.Exception.Message)" }
        continue
      }
      $entry=[double]$p.avg_entry_price
      $trailPct=if($protectMode){ 0.005 }else{ $TRAIL_PCT }   # 0.5% in protect mode vs 1% normal
      $minTrail=if($protectMode){ 0.8*$atr5 }else{ 1.5*$atr5 }
      $trail=[math]::Max($trailPct*$price,$minTrail)
      $floor=[math]::Round($entry-[math]::Max($INIT_STOP_PCT*$entry,1.5*$atr5),2)
      $desired=[math]::Round([math]::Max($price-$trail,$floor),2)
      $ceil=[math]::Round($entry*(1+$CEIL_PCT),2)
      $live="new","held","accepted","partially_filled","pending_new"
      # scan ALL live orders + their legs (bracket stop sits as a leg under the BUY parent)
      $allo=@(Invoke-RestMethod -Uri "$base/v2/orders?status=all&symbols=$s&limit=30&direction=desc&nested=true" -Headers $h)
      $curStop=0; $stopId=$null
      foreach($o in $allo){ if($o.type -eq "stop" -and $o.side -eq "sell" -and ($live -contains $o.status) -and $o.stop_price){ $curStop=[double]$o.stop_price; $stopId=$o.id }; foreach($l in $o.legs){ if($l.type -eq "stop" -and $l.side -eq "sell" -and ($live -contains $l.status) -and $l.stop_price){ $curStop=[double]$l.stop_price; $stopId=$l.id } } }
      if(-not $stopId){ try{ PlaceOCO $s $qty $ceil $floor; Stamp "$s protect OCO stop $floor" }catch{ Stamp "$s already protected (bracket); skip re-arm" } }
      elseif($desired -gt $curStop+0.02){ $pb=@{stop_price="$desired"}|ConvertTo-Json; try{ Invoke-RestMethod -Uri "$base/v2/orders/$stopId" -Method Patch -Headers $h -Body $pb -ContentType "application/json"|Out-Null; Stamp "$s TRAIL $curStop->$desired (price $price)" }catch{ Stamp "$s trail patch err $($_.ErrorDetails.Message)" } }
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
    if($e9[-1] -le $e21[-1]){ Stamp "$s EMA9<EMA21 - downtrend, skip"; continue }   # 9/21 EMA trend filter
    $score=[math]::Round(($price-$vwap)/$vwap*100,2)
    if($score -gt 4.0){ Stamp "$s too extended +${score}% above VWAP - missed the move, skip"; continue }  # late-entry filter
    if($noNewEntries){ Stamp "$s skip - no new entries after 3PM ET"; continue }
    $cands+=[pscustomobject]@{S=$s;Price=$price;Atr=$atr5;Rsi=$rsiNow;Score=$score}
    Stamp "$s CANDIDATE OK (RSI $rsiNow, +$score% vs VWAP)"
  }catch{ Stamp "$s err $($_.Exception.Message)" }
}

# Pass 2: fill free slots with the strongest candidates
$committed=$held+$pendingBuys
$slots=$MAX_POS-$committed
# CASH-ONLY guard: never open new positions on margin
$affordable=[math]::Floor([double]$acct.cash/$perBudget)
if($affordable -lt $slots){ $slots=[math]::Max(0,$affordable) }
Stamp "slots: held=$held pending=$pendingBuys free=$slots candidates=$($cands.Count) cash=$([math]::Round([double]$acct.cash,2)) (cash-only, no margin)"
if($slots -gt 0 -and -not $killed -and $cands.Count -gt 0){
  foreach($cd in (@($cands | Sort-Object Score -Descending) | Select-Object -First $slots)){
    $ref=$cd.Price; $lot=[int][math]::Floor($perBudget/$ref); if($lot -lt 1){ continue }
    $stopDist=[math]::Max($INIT_STOP_PCT*$ref,1.5*$cd.Atr)
    $tp=[math]::Round($ref*(1+$CEIL_PCT),2); $stopP=[math]::Round($ref-$stopDist,2)
    try{ PlaceBracket $cd.S $lot $tp $stopP; Stamp "$($cd.S) MARKET BUY $lot (~$ref) stop $stopP tp $tp (trailing after fill)" }catch{ Stamp "$($cd.S) order err $($_.ErrorDetails.Message)" }
  }
}
