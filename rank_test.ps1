# When several stocks signal on the SAME day and we only have 3 slots, which should we pick?
# Compares: deepest dip (lowest cumRSI2) / shallowest / list-order / random-ish (all signals avg).
$ErrorActionPreference="Stop"
$k=$env:APCA_API_KEY_ID; $s=$env:APCA_API_SECRET_KEY; if(-not $k){ foreach($l in (Get-Content (Join-Path $PSScriptRoot "..\.env"))){ if($l -match "^\s*APCA_API_KEY_ID\s*=\s*(.+)$"){$k=$Matches[1].Trim()}; if($l -match "^\s*APCA_API_SECRET_KEY\s*=\s*(.+)$"){$s=$Matches[1].Trim()} } }; $h=@{ "APCA-API-KEY-ID"=$k; "APCA-API-SECRET-KEY"=$s }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($cl,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $dd=$cl[$j]-$cl[$j-1]; if($dd -gt 0){$g+=$dd}else{$l+=-$dd} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($cl,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$cl[$j]}; $s/$p }
$UNI=@("NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL")
$BK=@{}; "loading..."
foreach($s in $UNI){ try{ $b=Bars $s; if($b.Count -ge 260){ $BK[$s]=$b } }catch{} }
# For every (stock, day) signal: record date, cumRSI2, list-order index, and the trade's forward return.
$sig=@()
foreach($s in $BK.Keys){
  $ord=[array]::IndexOf($UNI,$s)
  $b=$BK[$s]; $cl=@($b|ForEach-Object{[double]$_.c}); $dt=@($b|ForEach-Object{$_.t.Substring(0,10)})
  for($i=201;$i -lt $cl.Count-1;$i++){
    $sma=SmaN $cl $i 200; if($sma -eq $null){ continue }
    $r2=(RsiN $cl $i 2)+(RsiN $cl ($i-1) 2)
    if($cl[$i] -gt $sma -and $r2 -lt 35){
      # simulate the trade from here: exit RSI2>=65 or 10 days
      $e=$cl[$i]; $ret=$null
      for($j=$i+1;$j -lt [math]::Min($i+11,$cl.Count);$j++){
        if((RsiN $cl $j 2) -ge 65 -or ($j-$i) -ge 10){ $ret=($cl[$j]-$e)/$e; break }
      }
      if($ret -ne $null){ $sig+=[pscustomobject]@{D=$dt[$i];S=$s;R2=$r2;Ord=$ord;Ret=$ret} }
    }
  }
}
"total signals: $($sig.Count)"
$byDay=$sig | Group-Object D
$multi=@($byDay | Where-Object { $_.Count -ge 2 })
"days with 2+ competing signals: $($multi.Count)`n"
function Avg($a){ if($a.Count -eq 0){return 0}; [math]::Round((($a|Measure-Object -Average).Average)*100,3) }
function WinP($a){ if($a.Count -eq 0){return 0}; [math]::Round((@($a|Where-Object{$_ -gt 0}).Count)/$a.Count*100,1) }
# On each competing day, take up to 3 by each rule and record their returns
$deep=@();$shallow=@();$listord=@();$allsig=@()
foreach($g in $multi){
  $rows=$g.Group
  foreach($r in ($rows | Sort-Object R2 | Select-Object -First 3)){ $deep+=$r.Ret }
  foreach($r in ($rows | Sort-Object R2 -Descending | Select-Object -First 3)){ $shallow+=$r.Ret }
  foreach($r in ($rows | Sort-Object Ord | Select-Object -First 3)){ $listord+=$r.Ret }
  foreach($r in $rows){ $allsig+=$r.Ret }
}
"=== on days where signals COMPETE for 3 slots, which pick wins? ==="
"{0,-34} picks {1,5}  win {2,5}%  avg/trade {3,7}%" -f "DEEPEST dip (lowest cumRSI2)",$deep.Count,(WinP $deep),(Avg $deep)
"{0,-34} picks {1,5}  win {2,5}%  avg/trade {3,7}%" -f "SHALLOWEST dip (highest cumRSI2)",$shallow.Count,(WinP $shallow),(Avg $shallow)
"{0,-34} picks {1,5}  win {2,5}%  avg/trade {3,7}%" -f "LIST ORDER (current bot)",$listord.Count,(WinP $listord),(Avg $listord)
"{0,-34} picks {1,5}  win {2,5}%  avg/trade {3,7}%" -f "ALL signals (no slot limit)",$allsig.Count,(WinP $allsig),(Avg $allsig)
""
"=== does a deeper dip predict a bigger bounce? (all signals bucketed) ==="
foreach($b in @(@(0,5),@(5,10),@(10,20),@(20,30),@(30,35))){
  $sel=@($sig | Where-Object { $_.R2 -ge $b[0] -and $_.R2 -lt $b[1] } | ForEach-Object { $_.Ret })
  "cumRSI2 {0,2}-{1,2}:  n={2,5}  win {3,5}%  avg {4,7}%" -f $b[0],$b[1],$sel.Count,(WinP $sel),(Avg $sel)
}

