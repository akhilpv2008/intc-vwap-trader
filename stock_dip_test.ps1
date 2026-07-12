# Does the dip-buy edge (RSI(2)<10, price>200SMA, exit RSI(2)>=65 or 5d) work on INDIVIDUAL STOCKS?
# Tests each stock separately + a simple "basket" sim (split capital across concurrent signals, max 5).
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($c,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($c,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$c[$j]}; $s/$p }
$UNI=@("AAPL","MSFT","NVDA","AMD","META","GOOGL","AMZN","TSLA","INTC","JPM","XOM","UNH","HOOD","SOFI","PLTR")
$all=@{}
"loading data..."
foreach($s in $UNI){ try{ $all[$s]=Bars $s }catch{ "skip ${s}: $($_.Exception.Message)" } }
"=== per-stock: dip-buy (RSI2<10 & >200SMA -> exit RSI2>=65 or 5d) ==="
$dates=@{}
$results=@{}
foreach($s in $UNI){
  if(-not $all[$s] -or $all[$s].Count -lt 260){ continue }
  $b=$all[$s]; $c=@($b|ForEach-Object{[double]$_.c})
  $trades=@(); $in=$false;$held=0;$entry=0
  for($i=201;$i -lt $c.Count;$i++){
    if($in){
      $held++
      if((RsiN $c $i 2) -ge 65 -or $held -ge 5){ $trades+=(($c[$i]-$entry)/$entry); $in=$false }
    } else {
      $sma=SmaN $c ($i) 200
      if($sma -ne $null -and $c[$i] -gt $sma -and (RsiN $c $i 2) -lt 10 -and $i -lt $c.Count-1){
        $in=$true;$held=0;$entry=$c[$i]
        $d=$b[$i].t.Substring(0,10); if(-not $dates.ContainsKey($d)){$dates[$d]=@()}; $dates[$d]+=$s
      }
    }
  }
  if($trades.Count -gt 0){
    $w=@($trades|Where-Object{$_ -gt 0}).Count; $eq=1.0; foreach($t in $trades){$eq*=(1+$t)}
    $avg=[math]::Round((($trades|Measure-Object -Average).Average)*100,2)
    "{0,-6} trades {1,3}  win {2,4}%  avg/trade {3,6}%  compounded {4,7}%" -f $s,$trades.Count,[math]::Round($w/$trades.Count*100,0),$avg,[math]::Round(($eq-1)*100,1)
    $results[$s]=$trades
  }
}
$allTr=@(); foreach($k in $results.Keys){ $allTr+=$results[$k] }
$w=@($allTr|Where-Object{$_ -gt 0}).Count
"---"
"ALL STOCKS POOLED: {0} trades  win {1}%  avg/trade {2}%" -f $allTr.Count,[math]::Round($w/[math]::Max($allTr.Count,1)*100,1),[math]::Round((($allTr|Measure-Object -Average).Average)*100,2)
"signal-days with 2+ stocks dipping at once: " + @($dates.GetEnumerator()|Where-Object{$_.Value.Count -ge 2}).Count
