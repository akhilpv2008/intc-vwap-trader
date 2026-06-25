# Out-of-sample check: does the mean-reversion edge (buy RSI(2)<10, exit next close) hold in OTHER eras?
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
function Bars($s,$start,$end){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&end=${end}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
function Rsi($v,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$v[$j]-$v[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function Stats($name,$rets){
  $eq=1.0;$peak=1.0;$maxdd=0.0;$w=0;$n=0
  foreach($r in $rets){ $eq*=(1+$r); if($eq -gt $peak){$peak=$eq}; $dd=($peak-$eq)/$peak; if($dd -gt $maxdd){$maxdd=$dd}; if($r -ne 0){$n++; if($r -gt 0){$w++}} }
  $m=($rets|Measure-Object -Average).Average
  $sd=[math]::Sqrt((($rets|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$rets.Count)
  $sh=if($sd -gt 0){[math]::Round($m/$sd*[math]::Sqrt(252),2)}else{0}
  "{0,-40} ret {1,7}%  Sharpe {2,6}  maxDD {3,5}%  trades {4,4}  win {5,4}%" -f $name,[math]::Round(($eq-1)*100,1),$sh,[math]::Round($maxdd*100,1),$n,[math]::Round(($(if($n){$w/$n*100}else{0})),0)
}
function MRtest($sym,$start,$end){
  $b=Bars $sym $start $end; if($b.Count -lt 100){ "${sym} ${start}: only $($b.Count) bars"; return }
  $c=@($b|ForEach-Object{[double]$_.c})
  $bh=@(); for($i=1;$i -lt $c.Count;$i++){ $bh+=($c[$i]-$c[$i-1])/$c[$i-1] }
  $mr=@(); for($i=2;$i -lt $c.Count;$i++){ $r=Rsi $c ($i-1) 2; if($r -lt 10){ $mr+=($c[$i]-$c[$i-1])/$c[$i-1] }else{ $mr+=0 } }
  "--- ${sym}  ${start} -> ${end}  ($($b.Count) days) ---"
  Stats "  Buy & hold" $bh
  Stats "  Mean-revert (RSI2<10, 1-day hold)" $mr
}
"############ OUT-OF-SAMPLE ERA 1: 2010-2015 ############"
MRtest "QQQ" "2010-01-01" "2015-01-01"
MRtest "TQQQ" "2011-01-01" "2015-01-01"
"############ OUT-OF-SAMPLE ERA 2: 2015-2020 (incl 2018 selloff) ############"
MRtest "QQQ" "2015-01-01" "2020-01-01"
MRtest "TQQQ" "2015-01-01" "2020-01-01"
"############ ERA 3: 2022 BEAR YEAR (stress test) ############"
MRtest "QQQ" "2022-01-01" "2023-01-01"
MRtest "TQQQ" "2022-01-01" "2023-01-01"
