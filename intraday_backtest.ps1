# Intraday backtest of the live bot logic on real 5-min bars (last ~45 days).
# Parametrized: trailing-stop %, and max trades/day (to test the "fewer trades" idea).
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start=(Get-Date).ToUniversalTime().AddDays(-45).ToString("yyyy-MM-dd")
function Bars5($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
function EmaArr($v,$p){ $k=2.0/($p+1); $o=@($v[0]); for($i=1;$i -lt $v.Count;$i++){ $o+=($v[$i]*$k+$o[$i-1]*(1-$k)) }; $o }
function RsiAt($c,$i,$p=14){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; return 100-100/(1+($g/$p)/$al) }
function BT($sym,$trail,$initStop,$maxPerDay){
  $b=Bars5 $sym; if($b.Count -lt 50){ return "${sym}: no data" }
  $c=@($b|ForEach-Object{[double]$_.c}); $e12=EmaArr $c 12;$e26=EmaArr $c 26;$macd=@();for($i=0;$i -lt $c.Count;$i++){$macd+=($e12[$i]-$e26[$i])};$sig=EmaArr $macd 9
  $rsi=@();for($i=0;$i -lt $c.Count;$i++){$rsi+=(RsiAt $c $i 14)}
  $inpos=$false;$entry=0;$hw=0;$stop=0;$curDay="";$pv=0;$vv=0;$rets=@();$w=0;$l=0;$dayTrades=0
  for($i=1;$i -lt $b.Count;$i++){
    $day=$b[$i].t.Substring(0,10)
    if($day -ne $curDay){ if($inpos){$r=([double]$b[$i-1].c-$entry)/$entry;$rets+=$r;if($r -gt 0){$w++}else{$l++};$inpos=$false}; $curDay=$day;$pv=0;$vv=0;$dayTrades=0 }
    $tp=([double]$b[$i].h+[double]$b[$i].l+[double]$b[$i].c)/3;$pv+=$tp*[double]$b[$i].v;$vv+=[double]$b[$i].v;$vwap=if($vv -gt 0){$pv/$vv}else{[double]$b[$i].c}
    $px=[double]$b[$i].c;$lo=[double]$b[$i].l;$isLast=($i -eq $b.Count-1 -or $b[$i+1].t.Substring(0,10) -ne $day)
    if($inpos){
      if($px -gt $hw){$hw=$px}; $ns=$hw*(1-$trail); if($ns -gt $stop){$stop=$ns}
      if($lo -le $stop){$r=($stop-$entry)/$entry;$rets+=$r;if($r -gt 0){$w++}else{$l++};$inpos=$false}
      elseif($isLast){$r=($px-$entry)/$entry;$rets+=$r;if($r -gt 0){$w++}else{$l++};$inpos=$false}
    } else {
      $bull=($px -gt [double]$b[$i].o);$rok=($rsi[$i] -gt 40 -and $rsi[$i] -lt 72 -and $rsi[$i] -ge $rsi[$i-1]);$mok=($macd[$i] -gt $sig[$i])
      if(-not $isLast -and $dayTrades -lt $maxPerDay -and $px -gt $vwap -and $bull -and $rok -and $mok){$inpos=$true;$entry=$px;$hw=$px;$stop=$px*(1-$initStop);$dayTrades++}
    }
  }
  $n=$w+$l; if($n -eq 0){return "${sym}: 0 trades"}
  $eq=1.0;foreach($r in $rets){$eq*=(1+$r)}
  return [pscustomobject]@{Sym=$sym;Trades=$n;Win=[math]::Round($w/$n*100,1);Ret=[math]::Round(($eq-1)*100,1)}
}
"=== A) CURRENT logic (1% trail, unlimited trades/day) on GENERAL STOCKS ==="
foreach($s in "INTC","HOOD","SOFI","AFRM","NVDA","AMD"){ $r=BT $s 0.01 0.01 99; if($r -is [string]){$r}else{ "{0,-6} {1,3} trades  win {2,5}%  return {3,6}%" -f $r.Sym,$r.Trades,$r.Win,$r.Ret } }
"=== B) SIMPLER variant (2.5% wide stop, MAX 1 trade/day) ==="
foreach($s in "TQQQ","SQQQ","INTC","NVDA"){ $r=BT $s 0.025 0.025 1; if($r -is [string]){$r}else{ "{0,-6} {1,3} trades  win {2,5}%  return {3,6}%" -f $r.Sym,$r.Trades,$r.Win,$r.Ret } }
