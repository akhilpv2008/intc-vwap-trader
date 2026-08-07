# Should the bot scan a BIG universe instead of 10 stocks?
# Tests the same dip signal (cumRSI2<35 & >200SMA, exit RSI2>=65 or 5d) across ~60 liquid names,
# and reports: per-stock results, pooled stats, and how many signals fire per day (opportunity count).
$ErrorActionPreference="Stop"
$k=$env:APCA_API_KEY_ID; $s=$env:APCA_API_SECRET_KEY; if(-not $k){ foreach($l in (Get-Content (Join-Path $PSScriptRoot "..\.env"))){ if($l -match "^\s*APCA_API_KEY_ID\s*=\s*(.+)$"){$k=$Matches[1].Trim()}; if($l -match "^\s*APCA_API_SECRET_KEY\s*=\s*(.+)$"){$s=$Matches[1].Trim()} } }; $h=@{ "APCA-API-KEY-ID"=$k; "APCA-API-SECRET-KEY"=$s }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($cl,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $dd=$cl[$j]-$cl[$j-1]; if($dd -gt 0){$g+=$dd}else{$l+=-$dd} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($cl,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$cl[$j]}; $s/$p }
$CURRENT=@("NVDA","AMD","INTC","HOOD","PLTR","META","MSFT","AMZN","GOOGL","AAPL")
$BIG=@("AAPL","MSFT","NVDA","AMZN","GOOGL","META","AVGO","TSLA","AMD","INTC","QCOM","TXN","MU","AMAT","LRCX","ADI","CRM","ADBE","ORCL","NOW","INTU","PANW","SNOW","NET","CRWD","DDOG","SHOP","UBER","ABNB","HOOD","PLTR","COIN","SQ","PYPL","SOFI","JPM","BAC","GS","MS","V","MA","AXP","WFC","C","UNH","JNJ","LLY","PFE","MRK","ABBV","XOM","CVX","COP","WMT","COST","HD","NKE","SBUX","MCD","DIS","BA","CAT","GE","HON","LMT")
$RES=@{}; $SIGDAYS=@{}
"loading $($BIG.Count) symbols..."
$loaded=0
foreach($s in $BIG){
  try{
    $b=Bars $s; if($b.Count -lt 260){ continue }
    $cl=@($b|ForEach-Object{[double]$_.c}); $dt=@($b|ForEach-Object{$_.t.Substring(0,10)})
    $trades=@(); $in=$false;$hd=0;$e=0
    for($i=201;$i -lt $cl.Count;$i++){
      if($in){ $hd++; if((RsiN $cl $i 2) -ge 65 -or $hd -ge 5){ $trades+=(($cl[$i]-$e)/$e); $in=$false } }
      else{
        $sma=SmaN $cl $i 200; if($sma -eq $null -or $i -ge $cl.Count-1){ continue }
        $r2=(RsiN $cl $i 2)+(RsiN $cl ($i-1) 2)
        if($cl[$i] -gt $sma -and $r2 -lt 35){ $in=$true;$hd=0;$e=$cl[$i]
          $k=$dt[$i]; if(-not $SIGDAYS.ContainsKey($k)){$SIGDAYS[$k]=0}; $SIGDAYS[$k]++ }
      }
    }
    if($trades.Count -gt 0){ $RES[$s]=$trades }
    $loaded++
  }catch{}
}
"loaded $loaded symbols`n"
function Stats($name,$syms){
  $all=@(); foreach($s in $syms){ if($RES.ContainsKey($s)){ $all+=$RES[$s] } }
  if($all.Count -eq 0){ "$name : none"; return }
  $w=@($all|Where-Object{$_ -gt 0}).Count
  $m=($all|Measure-Object -Average).Average
  "{0,-34} names {1,3}  trades {2,5}  win {3,5}%  avg/trade {4,7}%" -f $name,@($syms|Where-Object{$RES.ContainsKey($_)}).Count,$all.Count,[math]::Round($w/$all.Count*100,1),[math]::Round($m*100,3)
}
"=== CURRENT 10-stock basket vs BIG universe ==="
Stats "CURRENT (our 10)" $CURRENT
Stats "BIG universe (all loaded)" $BIG
""
"=== per-stock ranking in the BIG universe (avg % per trade) ==="
$rank=@()
foreach($s in $RES.Keys){ $t=$RES[$s]; $w=@($t|Where-Object{$_ -gt 0}).Count
  $rank+=[pscustomobject]@{S=$s;N=$t.Count;Win=[math]::Round($w/$t.Count*100,1);Avg=[math]::Round((($t|Measure-Object -Average).Average)*100,3)} }
"--- TOP 15 ---"
$rank | Sort-Object Avg -Descending | Select-Object -First 15 | ForEach-Object { "  {0,-6} trades {1,3}  win {2,5}%  avg {3,7}%" -f $_.S,$_.N,$_.Win,$_.Avg }
"--- WORST 10 ---"
$rank | Sort-Object Avg | Select-Object -First 10 | ForEach-Object { "  {0,-6} trades {1,3}  win {2,5}%  avg {3,7}%" -f $_.S,$_.N,$_.Win,$_.Avg }
""
$neg=@($rank|Where-Object{$_.Avg -lt 0}).Count
"names with NEGATIVE avg/trade: $neg of $($rank.Count)"
$multi=@($SIGDAYS.GetEnumerator()|Where-Object{$_.Value -ge 3}).Count
"days where 3+ signals fired at once: $multi (bot can only take 3 - competition for slots)"

