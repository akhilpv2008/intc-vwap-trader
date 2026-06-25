# strategy_lab.ps1 - honest head-to-head of DIFFERENT strategy families on daily bars (5yr).
# Goal: find anything that beats buy-and-hold on a RISK-ADJUSTED basis (Sharpe), not just raw return.
# Each strategy is fully invested or in cash on a given day (no leverage stacking), $10k start.
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
function Sma($v,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$v[$j]}; $s/$p }
function Rsi($v,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$v[$j]-$v[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
# metrics from a list of daily returns
function Stats($name,$rets){
  $eq=1.0; $peak=1.0; $maxdd=0.0; $w=0;$n=0
  foreach($r in $rets){ $eq*=(1+$r); if($eq -gt $peak){$peak=$eq}; $dd=($peak-$eq)/$peak; if($dd -gt $maxdd){$maxdd=$dd}; if($r -ne 0){$n++; if($r -gt 0){$w++}} }
  $m=($rets|Measure-Object -Average).Average
  $sd=[math]::Sqrt((($rets|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$rets.Count)
  $sharpe=if($sd -gt 0){[math]::Round($m/$sd*[math]::Sqrt(252),2)}else{0}
  "{0,-34} ret {1,7}%  Sharpe {2,6}  maxDD {3,5}%  daysIn {4,4}  win {5,4}%" -f $name,[math]::Round(($eq-1)*100,1),$sharpe,[math]::Round($maxdd*100,1),$n,[math]::Round(($(if($n){$w/$n*100}else{0})),0)
}

foreach($sym in "QQQ","SPY","TQQQ"){
  $b=Bars $sym; if($b.Count -lt 200){ "${sym}: insufficient"; continue }
  $o=@($b|ForEach-Object{[double]$_.o}); $c=@($b|ForEach-Object{[double]$_.c})
  "=========== $sym  ($($b.Count) days, $start -> now) ==========="

  # 1) Buy & hold (the bar to beat)
  $bh=@(); for($i=1;$i -lt $c.Count;$i++){ $bh+=($c[$i]-$c[$i-1])/$c[$i-1] }
  Stats "1) Buy & hold" $bh

  # 2) Overnight only: hold from prior close to today's open, cash intraday (overnight-drift anomaly)
  $on=@(); for($i=1;$i -lt $c.Count;$i++){ $on+=($o[$i]-$c[$i-1])/$c[$i-1] }
  Stats "2) Overnight only (close->open)" $on

  # 3) Intraday only: buy open, sell close (complement of #2)
  $id=@(); for($i=0;$i -lt $c.Count;$i++){ $id+=($c[$i]-$o[$i])/$o[$i] }
  Stats "3) Intraday only (open->close)" $id

  # 4) Daily trend-follow: hold next day only if close > 50d SMA, else cash
  $tf=@(); for($i=1;$i -lt $c.Count;$i++){ $s=Sma $c ($i-1) 50; if($s -ne $null -and $c[$i-1] -gt $s){ $tf+=($c[$i]-$c[$i-1])/$c[$i-1] }else{ $tf+=0 } }
  Stats "4) Trend-follow (hold > 50d SMA)" $tf

  # 5) Trend-follow 200d (slower)
  $tf2=@(); for($i=1;$i -lt $c.Count;$i++){ $s=Sma $c ($i-1) 200; if($s -ne $null -and $c[$i-1] -gt $s){ $tf2+=($c[$i]-$c[$i-1])/$c[$i-1] }else{ $tf2+=0 } }
  Stats "5) Trend-follow (hold > 200d SMA)" $tf2

  # 6) Mean-reversion: buy at close when RSI(2)<10, exit at next close (classic short-term MR)
  $mr=@(); for($i=2;$i -lt $c.Count;$i++){ $r=Rsi $c ($i-1) 2; if($r -lt 10){ $mr+=($c[$i]-$c[$i-1])/$c[$i-1] }else{ $mr+=0 } }
  Stats "6) Mean-revert (buy RSI(2)<10)" $mr

  # 7) Mean-reversion ONLY when above 200d SMA (buy dips in an uptrend) - widely cited combo
  $mr2=@(); for($i=2;$i -lt $c.Count;$i++){ $r=Rsi $c ($i-1) 2; $s=Sma $c ($i-1) 200; if($s -ne $null -and $c[$i-1] -gt $s -and $r -lt 10){ $mr2+=($c[$i]-$c[$i-1])/$c[$i-1] }else{ $mr2+=0 } }
  Stats "7) MR dips in uptrend (RSI2<10 & >200SMA)" $mr2
  ""
}
