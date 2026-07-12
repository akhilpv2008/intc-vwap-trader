# STRATEGY SHOOTOUT on the live basket (5yr daily): current dip logic vs morning-open entry vs
# three documented mean-reversion strategies. Pooled stats across all names.
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($c,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($c,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$c[$j]}; $s/$p }
$UNI=@("NVDA","AMD","INTC","HOOD","PLTR","META","MSFT","AMZN","GOOGL","AAPL")
$D=@{}
"loading..."
foreach($s in $UNI){ try{ $D[$s]=Bars $s }catch{} }
function Pool($name,$fn){
  $all=@()
  foreach($s in $UNI){
    $b=$D[$s]; if(-not $b -or $b.Count -lt 260){ continue }
    $c=@($b|ForEach-Object{[double]$_.c}); $o=@($b|ForEach-Object{[double]$_.o}); $hi=@($b|ForEach-Object{[double]$_.h})
    $all += (& $fn $c $o $hi)
  }
  if($all.Count -eq 0){ "$name : no trades"; return }
  $w=@($all|Where-Object{$_ -gt 0}).Count
  $avg=[math]::Round((($all|Measure-Object -Average).Average)*100,3)
  $sd=[math]::Sqrt((($all|ForEach-Object{$m=(($all|Measure-Object -Average).Average);($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$all.Count)
  "{0,-42} trades {1,4}  win {2,5}%  avg/trade {3,7}%" -f $name,$all.Count,[math]::Round($w/$all.Count*100,1),$avg
}
# 1) CURRENT: RSI2<10 & >200SMA, enter@close, exit RSI2>=65 or 5d
$cur={ param($c,$o,$hi)
  $t=@(); $in=$false;$hd=0;$e=0
  for($i=201;$i -lt $c.Count;$i++){
    if($in){ $hd++; if((RsiN $c $i 2) -ge 65 -or $hd -ge 5){ $t+=(($c[$i]-$e)/$e); $in=$false } }
    else{ $s=SmaN $c $i 200; if($s -and $c[$i] -gt $s -and (RsiN $c $i 2) -lt 10 -and $i -lt $c.Count-1){ $in=$true;$hd=0;$e=$c[$i] } } }
  ,$t }
# 2) MORNING: same signal at close, but ENTER NEXT MORNING AT OPEN (the user's ask)
$morn={ param($c,$o,$hi)
  $t=@(); $in=$false;$hd=0;$e=0
  for($i=201;$i -lt $c.Count;$i++){
    if($in){ $hd++; if((RsiN $c $i 2) -ge 65 -or $hd -ge 5){ $t+=(($c[$i]-$e)/$e); $in=$false } }
    else{ $s=SmaN $c $i 200; if($s -and $c[$i] -gt $s -and (RsiN $c $i 2) -lt 10 -and $i -lt $c.Count-1){ $in=$true;$hd=0;$e=$o[$i+1] } } }
  ,$t }
# 3) DOUBLE 7s (Connors): buy 7-day lowest close (>200SMA), sell 7-day highest close (cap 10d)
$d7={ param($c,$o,$hi)
  $t=@(); $in=$false;$hd=0;$e=0
  for($i=201;$i -lt $c.Count;$i++){
    if($in){ $hd++
      $mx=$c[($i-6)..$i]|Measure-Object -Maximum; if($c[$i] -ge $mx.Maximum -or $hd -ge 10){ $t+=(($c[$i]-$e)/$e); $in=$false } }
    else{ $s=SmaN $c $i 200; $mn=($c[($i-6)..$i]|Measure-Object -Minimum).Minimum
      if($s -and $c[$i] -gt $s -and $c[$i] -le $mn -and $i -lt $c.Count-1){ $in=$true;$hd=0;$e=$c[$i] } } }
  ,$t }
# 4) 3 DOWN DAYS: 3 consecutive lower closes (>200SMA); exit close > prior day's high or 5d
$dd3={ param($c,$o,$hi)
  $t=@(); $in=$false;$hd=0;$e=0
  for($i=201;$i -lt $c.Count;$i++){
    if($in){ $hd++; if($c[$i] -gt $hi[$i-1] -or $hd -ge 5){ $t+=(($c[$i]-$e)/$e); $in=$false } }
    else{ $s=SmaN $c $i 200
      if($s -and $c[$i] -gt $s -and $c[$i] -lt $c[$i-1] -and $c[$i-1] -lt $c[$i-2] -and $c[$i-2] -lt $c[$i-3] -and $i -lt $c.Count-1){ $in=$true;$hd=0;$e=$c[$i] } } }
  ,$t }
# 5) CUMULATIVE RSI2 (Connors): RSI2 today + yesterday < 35 (>200SMA); exit RSI2>=65 or 5d
$cum={ param($c,$o,$hi)
  $t=@(); $in=$false;$hd=0;$e=0
  for($i=201;$i -lt $c.Count;$i++){
    if($in){ $hd++; if((RsiN $c $i 2) -ge 65 -or $hd -ge 5){ $t+=(($c[$i]-$e)/$e); $in=$false } }
    else{ $s=SmaN $c $i 200; $r2=(RsiN $c $i 2)+(RsiN $c ($i-1) 2)
      if($s -and $c[$i] -gt $s -and $r2 -lt 35 -and $i -lt $c.Count-1){ $in=$true;$hd=0;$e=$c[$i] } } }
  ,$t }
"=== POOLED across basket (10 stocks, 5yr) ==="
Pool "1) CURRENT dip (enter@close)" $cur
Pool "2) Same signal, enter NEXT MORNING @open" $morn
Pool "3) Double 7s (7d-low buy, 7d-high sell)" $d7
Pool "4) 3 down days (exit > prior high)" $dd3
Pool "5) Cumulative RSI2 < 35" $cum
