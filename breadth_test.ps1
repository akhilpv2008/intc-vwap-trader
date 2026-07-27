# Does a BREADTH regime filter improve the dip-buyer?
# Rule tested: only take dip-buys when fewer than X% of the basket is below its own 200-day SMA.
# (Right now 6 of 11 names are below - so this decides whether the bot should stand down.)
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($c,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($c,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$c[$j]}; $s/$p }
$UNI=@("NVDA","AMD","INTC","HOOD","PLTR","META","MSFT","AMZN","GOOGL","AAPL")
$BARMAP=@{}; $CLOSEMAP=@{}; $DATEMAP=@{}
"loading..."
foreach($s in $UNI){ try{ $b=Bars $s; $BARMAP[$s]=$b; $CLOSEMAP[$s]=@($b|ForEach-Object{[double]$_.c}); $DATEMAP[$s]=@($b|ForEach-Object{$_.t.Substring(0,10)}) }catch{} }
# build a date-indexed breadth map: fraction of names ABOVE their 200SMA on each date
$breadth=@{}
$ref=$DATEMAP[$UNI[0]]
foreach($s in $UNI){
  if(-not $CLOSEMAP.ContainsKey($s) -or $CLOSEMAP[$s].Count -lt 260){ continue }
  $c=$CLOSEMAP[$s]; $d=$DATEMAP[$s]
  for($i=200;$i -lt $c.Count;$i++){
    $sma=SmaN $c $i 200
    if($sma -ne $null){
      $k=$d[$i]
      if(-not $breadth.ContainsKey($k)){ $breadth[$k]=@{up=0;tot=0} }
      $breadth[$k].tot++
      if($c[$i] -gt $sma){ $breadth[$k].up++ }
    }
  }
}
function Run($minBreadthPct){
  $all=@()
  foreach($s in $UNI){
    if(-not $CLOSEMAP.ContainsKey($s) -or $CLOSEMAP[$s].Count -lt 260){ continue }
    $c=$CLOSEMAP[$s]; $d=$DATEMAP[$s]
    $in=$false;$hd=0;$e=0
    for($i=201;$i -lt $c.Count;$i++){
      if($in){ $hd++; if((RsiN $c $i 2) -ge 65 -or $hd -ge 5){ $all+=(($c[$i]-$e)/$e); $in=$false } }
      else{
        $sma=SmaN $c $i 200; if($sma -eq $null -or $i -ge $c.Count-1){ continue }
        $r2=(RsiN $c $i 2)+(RsiN $c ($i-1) 2)
        $bk=$d[$i]; $bp=100.0
        if($breadth.ContainsKey($bk) -and $breadth[$bk].tot -gt 0){ $bp=$breadth[$bk].up/$breadth[$bk].tot*100 }
        if($c[$i] -gt $sma -and $r2 -lt 35 -and $bp -ge $minBreadthPct){ $in=$true;$hd=0;$e=$c[$i] }
      }
    }
  }
  if($all.Count -eq 0){ return "  no trades" }
  $w=@($all|Where-Object{$_ -gt 0}).Count
  $m=($all|Measure-Object -Average).Average
  $tot=1.0; foreach($x in $all){ $tot*=(1+$x) }
  "  trades {0,4}  win {1,5}%  avg/trade {2,7}%  compounded {3,9}%" -f $all.Count,[math]::Round($w/$all.Count*100,1),[math]::Round($m*100,3),[math]::Round(($tot-1)*100,1)
}
"=== BREADTH FILTER: require at least N% of basket ABOVE its 200SMA to buy ==="
"NO filter (current bot, buy any qualifying dip):"; Run 0
"require >=30% of basket healthy:"; Run 30
"require >=40% of basket healthy:"; Run 40
"require >=50% of basket healthy:"; Run 50
"require >=60% of basket healthy:"; Run 60
"require >=70% of basket healthy:"; Run 70

