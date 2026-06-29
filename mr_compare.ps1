# Compare TWO "buy the dip" (mean-reversion) versions vs buy & hold:
#  A) OVERNIGHT version - daily bars, holds 1-5 days (the proven approach)
#  B) INTRADAY-ONLY version - 5-min bars, buys intraday dips, FLAT by close (respects no-overnight rule)
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
function DBars($s,$start){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
function MBars($s,$start){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
function Sma($v,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$v[$j]}; $s/$p }
function RsiN($c,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function Stats($name,$rets){
  $eq=1.0;$peak=1.0;$maxdd=0.0;$w=0;$n=0
  foreach($r in $rets){ $eq*=(1+$r); if($eq -gt $peak){$peak=$eq}; $dd=($peak-$eq)/$peak; if($dd -gt $maxdd){$maxdd=$dd}; if($r -ne 0){$n++; if($r -gt 0){$w++}} }
  $m=($rets|Measure-Object -Average).Average
  $sd=[math]::Sqrt((($rets|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$rets.Count)
  $sh=if($sd -gt 0){[math]::Round($m/$sd*[math]::Sqrt(252),2)}else{0}
  "  {0,-34} ret {1,7}%  Sharpe {2,6}  maxDD {3,5}%  days/trades {4,4}  win {5,4}%" -f $name,[math]::Round(($eq-1)*100,1),$sh,[math]::Round($maxdd*100,1),$n,[math]::Round(($(if($n){$w/$n*100}else{0})),0)
}

"##################  A) OVERNIGHT dip-buyer (daily, 5yr)  ##################"
foreach($sym in "QQQ","TQQQ"){
  $b=DBars $sym "2020-06-01"; $c=@($b|ForEach-Object{[double]$_.c})
  "--- ${sym} ($($c.Count) days) ---"
  $bh=@(); for($i=1;$i -lt $c.Count;$i++){ $bh+=($c[$i]-$c[$i-1])/$c[$i-1] }; Stats "Buy & hold" $bh
  # buy at close when RSI(2)<10 & above 200SMA; hold (accrue daily) until RSI(2)>=65 or 5 days; else cash
  $mr=@(); $in=$false;$held=0
  for($i=3;$i -lt $c.Count;$i++){
    if($in){ $mr+=($c[$i]-$c[$i-1])/$c[$i-1]; $held++; if((RsiN $c $i 2) -ge 65 -or $held -ge 5){ $in=$false } }
    else{ $s=Sma $c ($i-1) 200; if($s -ne $null -and $c[$i-1] -gt $s -and (RsiN $c ($i-1) 2) -lt 10){ $in=$true;$held=0; $mr+=($c[$i]-$c[$i-1])/$c[$i-1]; if((RsiN $c $i 2) -ge 65){$in=$false} } else { $mr+=0 } }
  }
  Stats "OVERNIGHT dip-buyer (RSI2<10,>200SMA)" $mr
}

"`n##################  B) INTRADAY-ONLY dip-buyer (5-min, ~45d, FLAT by close)  ##################"
$start=(Get-Date).ToUniversalTime().AddDays(-45).ToString("yyyy-MM-dd")
foreach($sym in "QQQ","TQQQ"){
  $b=MBars $sym $start; if($b.Count -lt 100){ "${sym}: no intraday data"; continue }
  $c=@($b|ForEach-Object{[double]$_.c})
  "--- ${sym} ($($b.Count) 5-min bars) ---"
  # momentum baseline (what we run now): for reference
  $rets=@(); $in=$false;$entry=0;$hw=0;$stop=0;$curDay="";$pv=0;$vv=0
  $mrr=@(); $min2=$false;$men=0;$mstop=0;$cur2="";$pv2=0;$vv2=0
  for($i=14;$i -lt $b.Count;$i++){
    $day=$b[$i].t.Substring(0,10); $px=[double]$b[$i].c;$lo=[double]$b[$i].l;$hi=[double]$b[$i].h
    $isLast=($i -eq $b.Count-1 -or $b[$i+1].t.Substring(0,10) -ne $day)
    # ---- intraday MEAN-REVERSION ----
    if($day -ne $cur2){ if($min2){ $mrr+=($px-$men)/$men; $min2=$false }; $cur2=$day;$pv2=0;$vv2=0 }
    $tp=($hi+$lo+$px)/3;$pv2+=$tp*[double]$b[$i].v;$vv2+=[double]$b[$i].v;$vw=if($vv2 -gt 0){$pv2/$vv2}else{$px}
    $rsi=RsiN $c $i 14
    if($min2){
      if($lo -le $mstop){ $mrr+=($mstop-$men)/$men; $min2=$false }
      elseif($px -ge $vw -or $rsi -ge 55){ $mrr+=($px-$men)/$men; $min2=$false }   # reverted to VWAP / bounced -> exit
      elseif($isLast){ $mrr+=($px-$men)/$men; $min2=$false }
    } else {
      $bull=($px -gt [double]$b[$i].o)
      if(-not $isLast -and $px -lt $vw*0.995 -and $rsi -lt 30 -and $bull){ $min2=$true;$men=$px;$mstop=$px*0.98 }  # oversold dip turning up
    }
  }
  Stats "INTRADAY dip-buyer (flat by close)" $mrr
}
