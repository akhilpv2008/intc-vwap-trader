# Research claim: filtering mean-reversion by VOLATILITY REGIME improves win rate.
# Test: only take dip-buys when SPY 20-day realized volatility (a VIX proxy) is in a given band.
$ErrorActionPreference="Stop"
$k=$env:APCA_API_KEY_ID; $s=$env:APCA_API_SECRET_KEY; if(-not $k){ foreach($l in (Get-Content (Join-Path $PSScriptRoot "..\.env"))){ if($l -match "^\s*APCA_API_KEY_ID\s*=\s*(.+)$"){$k=$Matches[1].Trim()}; if($l -match "^\s*APCA_API_SECRET_KEY\s*=\s*(.+)$"){$s=$Matches[1].Trim()} } }; $h=@{ "APCA-API-KEY-ID"=$k; "APCA-API-SECRET-KEY"=$s }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($cl,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $dd=$cl[$j]-$cl[$j-1]; if($dd -gt 0){$g+=$dd}else{$l+=-$dd} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($cl,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$cl[$j]}; $s/$p }
# SPY 20-day annualised realised vol, indexed by date
"loading SPY for the volatility regime..."
$spy=Bars "SPY"
$sc=@($spy|ForEach-Object{[double]$_.c}); $sd=@($spy|ForEach-Object{$_.t.Substring(0,10)})
$VOL=@{}
for($i=21;$i -lt $sc.Count;$i++){
  $r=@(); for($j=$i-19;$j -le $i;$j++){ $r+=[math]::Log($sc[$j]/$sc[$j-1]) }
  $m=($r|Measure-Object -Average).Average
  $v=[math]::Sqrt((($r|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/($r.Count-1))*[math]::Sqrt(252)*100
  $VOL[$sd[$i]]=$v
}
$vals=@($VOL.Values|Sort-Object)
"vol range: min $([math]::Round($vals[0],1))  median $([math]::Round($vals[[int]($vals.Count/2)],1))  max $([math]::Round($vals[-1],1))"
$UNI=@("NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL")
$BK=@{}
foreach($s in $UNI){ try{ $b=Bars $s; if($b.Count -ge 260){ $BK[$s]=$b } }catch{} }
# collect every signal with the prevailing vol regime and its outcome
$sig=@()
foreach($s in $BK.Keys){
  $b=$BK[$s]; $cl=@($b|ForEach-Object{[double]$_.c}); $dt=@($b|ForEach-Object{$_.t.Substring(0,10)})
  $in=$false;$hd=0;$e=0;$vAt=0
  for($i=201;$i -lt $cl.Count;$i++){
    if($in){ $hd++
      if((RsiN $cl $i 2) -ge 65 -or $hd -ge 10){ $sig+=[pscustomobject]@{V=$vAt;R=(($cl[$i]-$e)/$e)}; $in=$false } }
    else{
      $sma=SmaN $cl $i 200; if($sma -eq $null -or $i -ge $cl.Count-1){ continue }
      $r2=(RsiN $cl $i 2)+(RsiN $cl ($i-1) 2)
      if($cl[$i] -gt $sma -and $r2 -lt 35){
        $k=$dt[$i]; if(-not $VOL.ContainsKey($k)){ continue }
        $in=$true;$hd=0;$e=$cl[$i];$vAt=$VOL[$k] }
    }
  }
}
function Rep($name,$sel){
  if($sel.Count -eq 0){ "{0,-40} none" -f $name; return }
  $w=@($sel|Where-Object{$_ -gt 0}).Count
  $m=($sel|Measure-Object -Average).Average
  "{0,-40} trades {1,4}  win {2,5}%  avg/trade {3,7}%" -f $name,$sel.Count,[math]::Round($w/$sel.Count*100,1),[math]::Round($m*100,3)
}
"`n=== total signals: $($sig.Count) ==="
Rep "ALL (current bot - no vol filter)" @($sig|ForEach-Object{$_.R})
"`n--- bucketed by SPY 20d realised vol ---"
foreach($b in @(@(0,12),@(12,16),@(16,20),@(20,25),@(25,35),@(35,200))){
  Rep ("vol {0,3}-{1,3}%" -f $b[0],$b[1]) @($sig|Where-Object{ $_.V -ge $b[0] -and $_.V -lt $b[1] }|ForEach-Object{$_.R})
}
"`n--- candidate filters (trade ONLY inside the band) ---"
Rep "only vol < 20%"        @($sig|Where-Object{ $_.V -lt 20 }|ForEach-Object{$_.R})
Rep "only vol < 25%"        @($sig|Where-Object{ $_.V -lt 25 }|ForEach-Object{$_.R})
Rep "only vol 12-25% (research pick)" @($sig|Where-Object{ $_.V -ge 12 -and $_.V -lt 25 }|ForEach-Object{$_.R})
Rep "only vol > 25% (high-fear only)" @($sig|Where-Object{ $_.V -ge 25 }|ForEach-Object{$_.R})

