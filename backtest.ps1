# Backtest of the TQQQ/SQQQ directional day-trade idea on ~1yr of DAILY bars.
# Rule (no lookahead): use YESTERDAY's QQQ trend -> if QQQ closed above its 20-day EMA = uptrend
# -> today go long TQQQ; else go long SQQQ. Enter at today's OPEN, exit at today's CLOSE
# (intraday, flat by close). Intraday stop ~2.5%. Skip "chaos" days (QQQ gap > 1.5%).
# This approximates the directional edge; the live bot adds intraday VWAP/RSI/MACD timing.
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"=$env:APCA_API_KEY_ID; "APCA-API-SECRET-KEY"=$env:APCA_API_SECRET_KEY }
if(-not $env:APCA_API_KEY_ID){ $h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" } }
$start="2025-06-01"
function Bars($s){ (Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=400&feed=iex" -Headers $h).bars }
$qqq=Bars "QQQ"; $tqqq=Bars "TQQQ"; $sqqq=Bars "SQQQ"
function ByDate($b){ $t=@{}; foreach($x in $b){ $t[$x.t.Substring(0,10)]=$x }; $t }
$T=ByDate $tqqq; $S=ByDate $sqqq
$closes=@($qqq|ForEach-Object{[double]$_.c})
# EMA20 of QQQ
$k=2.0/21; $ema=@($closes[0]); for($i=1;$i -lt $closes.Count;$i++){ $ema+=($closes[$i]*$k+$ema[$i-1]*(1-$k)) }
$STOP=0.025; $BUD=10000.0
$eq=10000.0; $peak=10000.0; $maxDD=0.0; $rets=@(); $wins=0; $losses=0; $skips=0; $tq=0;$sq=0; $sumWin=0.0;$sumLoss=0.0
for($i=21;$i -lt $qqq.Count;$i++){
  $d=$qqq[$i].t.Substring(0,10)
  $bull = $closes[$i-1] -gt $ema[$i-1]
  $sym = if($bull){"TQQQ"}else{"SQQQ"}
  if($bull){$tq++}else{$sq++}
  if(-not $T.ContainsKey($d) -or -not $S.ContainsKey($d)){ continue }
  $etf = if($bull){ $T[$d] }else{ $S[$d] }
  # chaos filter: skip if QQQ gapped >1.5% overnight
  $gap=[math]::Abs(([double]$qqq[$i].o-$closes[$i-1])/$closes[$i-1])
  if($gap -gt 0.015){ $skips++; $rets+=0.0; continue }
  $o=[double]$etf.o; $c=[double]$etf.c; $lo=[double]$etf.l
  # long the ETF from open to close, with intraday stop
  if(($lo-$o)/$o -le -$STOP){ $r=-$STOP } else { $r=($c-$o)/$o }
  $rets+=$r; $pl=$r*$BUD; $eq+=$pl
  if($r -gt 0){ $wins++; $sumWin+=$pl } elseif($r -lt 0){ $losses++; $sumLoss+=$pl }
  if($eq -gt $peak){ $peak=$eq }; $dd=($peak-$eq)/$peak; if($dd -gt $maxDD){ $maxDD=$dd }
}
$n=$wins+$losses
$mean=($rets|Measure-Object -Average).Average
$sd=[math]::Sqrt((($rets|ForEach-Object{($_-$mean)*($_-$mean)})|Measure-Object -Sum).Sum/$rets.Count)
$sharpe= if($sd -gt 0){ [math]::Round($mean/$sd*[math]::Sqrt(252),2) }else{0}
$totRet=[math]::Round(($eq-10000)/10000*100,1)
"=== TQQQ/SQQQ daily backtest ($start -> now) ==="
"trading days simulated: $($rets.Count)  (TQQQ-days $tq / SQQQ-days $sq / chaos-skips $skips)"
"final equity: `$$([math]::Round($eq,0))  | total return: $totRet%"
"win rate: $([math]::Round($wins/[math]::Max($n,1)*100,1))%  ($wins W / $losses L)"
"avg win: `$$([math]::Round($sumWin/[math]::Max($wins,1),2))  avg loss: `$$([math]::Round($sumLoss/[math]::Max($losses,1),2))"
"max drawdown: $([math]::Round($maxDD*100,1))%   Sharpe (annualized): $sharpe"
