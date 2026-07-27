# DEFINITIVE TEST: "scan lots of stocks every morning, buy the ones going up, sell by close"
# vs our dip-buyer. Same 65-stock universe, same 5 years, same data. Let the numbers decide.
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($cl,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $dd=$cl[$j]-$cl[$j-1]; if($dd -gt 0){$g+=$dd}else{$l+=-$dd} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($cl,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$cl[$j]}; $s/$p }
$UNI=@("AAPL","MSFT","NVDA","AMZN","GOOGL","META","AVGO","TSLA","AMD","INTC","QCOM","TXN","MU","AMAT","LRCX","ADI","CRM","ADBE","ORCL","NOW","INTU","PANW","SNOW","NET","CRWD","DDOG","SHOP","UBER","ABNB","HOOD","PLTR","COIN","SQ","PYPL","SOFI","JPM","BAC","GS","MS","V","MA","AXP","WFC","C","UNH","JNJ","LLY","PFE","MRK","ABBV","XOM","CVX","COP","WMT","COST","HD","NKE","SBUX","MCD","DIS","BA","CAT","GE","HON","LMT")
$BK=@{}
"loading $($UNI.Count) stocks..."
foreach($s in $UNI){ try{ $b=Bars $s; if($b.Count -ge 260){ $BK[$s]=$b } }catch{} }
"loaded $($BK.Count)`n"
function Report($name,$rets){
  if($rets.Count -eq 0){ "$name : no trades"; return }
  $w=@($rets|Where-Object{$_ -gt 0}).Count
  $m=($rets|Measure-Object -Average).Average
  $sd=[math]::Sqrt((($rets|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$rets.Count)
  $edge=if($sd -gt 0){[math]::Round($m/$sd,4)}else{0}
  "{0,-44} trades {1,6}  win {2,5}%  avg/trade {3,8}%  edge/risk {4,8}" -f $name,$rets.Count,[math]::Round($w/$rets.Count*100,1),[math]::Round($m*100,4),$edge
}
# ---------- DAY TRADING variants (buy at open, sell same day at close) ----------
$dtGap=@(); $dtStrong=@(); $dtAll=@(); $dtTrend=@()
foreach($s in $BK.Keys){
  $b=$BK[$s]
  $o=@($b|ForEach-Object{[double]$_.o}); $cl=@($b|ForEach-Object{[double]$_.c})
  for($i=201;$i -lt $cl.Count;$i++){
    $intraday=($cl[$i]-$o[$i])/$o[$i]
    $dtAll+=$intraday                                                    # buy every stock every day
    $gap=($o[$i]-$cl[$i-1])/$cl[$i-1]
    if($gap -gt 0.01){ $dtGap+=$intraday }                               # gapped UP >1% at the open
    $r5=($cl[$i-1]-$cl[$i-6])/$cl[$i-6]
    if($r5 -gt 0.03){ $dtStrong+=$intraday }                             # strong 5-day momentum
    $sma=SmaN $cl ($i-1) 50
    if($sma -ne $null -and $cl[$i-1] -gt $sma -and $cl[$i-1] -gt $cl[$i-2]){ $dtTrend+=$intraday }  # uptrend + rising
  }
}
# ---------- OUR SWING dip-buyer on the same universe ----------
$swing=@()
foreach($s in $BK.Keys){
  $b=$BK[$s]; $cl=@($b|ForEach-Object{[double]$_.c})
  $in=$false;$hd=0;$e=0
  for($i=201;$i -lt $cl.Count;$i++){
    if($in){ $hd++; if((RsiN $cl $i 2) -ge 65 -or $hd -ge 10){ $swing+=(($cl[$i]-$e)/$e); $in=$false } }
    else{ $sma=SmaN $cl $i 200; if($sma -eq $null -or $i -ge $cl.Count-1){ continue }
      $r2=(RsiN $cl $i 2)+(RsiN $cl ($i-1) 2)
      if($cl[$i] -gt $sma -and $r2 -lt 35){ $in=$true;$hd=0;$e=$cl[$i] } } }
}
"=== DAY TRADING (buy morning, sell by close) across all $($BK.Count) stocks ==="
Report "buy ANY stock at open, sell at close"      $dtAll
Report "buy stocks that GAPPED UP >1%"             $dtGap
Report "buy stocks with strong 5-day momentum"     $dtStrong
Report "buy uptrend + rising yesterday"            $dtTrend
""
"=== OUR SWING DIP-BUYER (same stocks, hold 1-10 days) ==="
Report "dip-buy: cumRSI2<35 & >200SMA"             $swing
""
"NOTE: real day trading also pays spread+slippage on EVERY trade (~0.05-0.1% each way)."
$costed = $dtGap | ForEach-Object { $_ - 0.001 }
Report "gapped-up day trade AFTER 0.1% costs"      $costed
