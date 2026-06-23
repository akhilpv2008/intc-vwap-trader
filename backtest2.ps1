# Compare several approaches over the same ~1yr, so we know what actually beats what.
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start="2020-06-01"
function Bars($s){ $all=@(); $pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){ $u+="&page_token=$pt" }; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
$qqq=Bars "QQQ"; $tqqq=Bars "TQQQ"; $sqqq=Bars "SQQQ"
function ByDate($b){ $t=@{}; foreach($x in $b){ $t[$x.t.Substring(0,10)]=$x }; $t }
$T=ByDate $tqqq; $S=ByDate $sqqq
$qc=@($qqq|ForEach-Object{[double]$_.c})
$k=2.0/21; $ema=@($qc[0]); for($i=1;$i -lt $qc.Count;$i++){ $ema+=($qc[$i]*$k+$ema[$i-1]*(1-$k)) }
function BH($b){ [math]::Round(([double]$b[-1].c-[double]$b[0].c)/[double]$b[0].c*100,1) }
function Sharpe($r){ $m=($r|Measure-Object -Average).Average; $sd=[math]::Sqrt((($r|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$r.Count); if($sd -gt 0){[math]::Round($m/$sd*[math]::Sqrt(252),2)}else{0} }
$STOP=0.025
# Strategy A: intraday TQQQ/SQQQ trend (open->close). B: TQQQ-or-cash. C: overnight TQQQ/SQQQ.
$rA=@();$rB=@();$rC=@()
for($i=21;$i -lt $qqq.Count-1;$i++){
  $d=$qqq[$i].t.Substring(0,10); $bull=$qc[$i-1] -gt $ema[$i-1]
  if(-not $T.ContainsKey($d) -or -not $S.ContainsKey($d)){ continue }
  $gap=[math]::Abs(([double]$qqq[$i].o-$qc[$i-1])/$qc[$i-1]); if($gap -gt 0.015){ $rA+=0;$rB+=0;$rC+=0; continue }
  $etf= if($bull){$T[$d]}else{$S[$d]}; $o=[double]$etf.o;$c=[double]$etf.c;$lo=[double]$etf.l
  $ra= if(($lo-$o)/$o -le -$STOP){-$STOP}else{($c-$o)/$o}; $rA+=$ra
  if($bull){ $o2=[double]$T[$d].o;$c2=[double]$T[$d].c;$l2=[double]$T[$d].l; $rB+= if(($l2-$o2)/$o2 -le -$STOP){-$STOP}else{($c2-$o2)/$o2} } else { $rB+=0 }
  $dn=$qqq[$i+1].t.Substring(0,10); $e2= if($bull){$T}else{$S}; if($e2.ContainsKey($d) -and $e2.ContainsKey($dn)){ $rC+=([double]$e2[$dn].c-[double]$e2[$d].c)/[double]$e2[$d].c } else { $rC+=0 }
}
function Eq($r){ $e=10000.0; foreach($x in $r){ $e*=(1+$x) }; [math]::Round(($e-10000)/100,1) }
"=== Benchmarks (just hold, $start -> now) ==="
"Buy & hold QQQ:   $(BH $qqq)%"
"Buy & hold TQQQ:  $(BH $tqqq)%   <-- the bar to beat"
"Buy & hold SQQQ:  $(BH $sqqq)%"
""
"=== Active strategies (same period) ==="
"A) intraday TQQQ/SQQQ trend:  $(Eq $rA)%   Sharpe $(Sharpe $rA)"
"B) intraday TQQQ-or-cash:     $(Eq $rB)%   Sharpe $(Sharpe $rB)"
"C) overnight TQQQ/SQQQ trend: $(Eq $rC)%   Sharpe $(Sharpe $rC)"
