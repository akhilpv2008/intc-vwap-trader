# Can we improve the dip-buyer's EXIT? Entry is fixed (cumRSI2<35 & >200SMA).
# Tests: RSI exit thresholds, max-hold length, profit targets, first-up-close, and ATR stops.
$ErrorActionPreference="Stop"
$k=$env:APCA_API_KEY_ID; $s=$env:APCA_API_SECRET_KEY; if(-not $k){ foreach($l in (Get-Content (Join-Path $PSScriptRoot "..\.env"))){ if($l -match "^\s*APCA_API_KEY_ID\s*=\s*(.+)$"){$k=$Matches[1].Trim()}; if($l -match "^\s*APCA_API_SECRET_KEY\s*=\s*(.+)$"){$s=$Matches[1].Trim()} } }; $h=@{ "APCA-API-KEY-ID"=$k; "APCA-API-SECRET-KEY"=$s }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($cl,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $dd=$cl[$j]-$cl[$j-1]; if($dd -gt 0){$g+=$dd}else{$l+=-$dd} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($cl,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$cl[$j]}; $s/$p }
$UNI=@("NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL")
$BK=@{}
"loading..."
foreach($s in $UNI){ try{ $BK[$s]=Bars $s }catch{} }
# exitRsi: sell when RSI2 >= this ; maxHold: days cap ; profitTgt: sell at +X% (0=off)
# stopPct: hard stop as % below entry (0=off) ; firstUp: sell on first higher close (bool)
function Test($name,$exitRsi,$maxHold,$profitTgt,$stopPct,$firstUp){
  $all=@()
  foreach($s in $UNI){
    if(-not $BK.ContainsKey($s)){ continue }
    $b=$BK[$s]; if($b.Count -lt 260){ continue }
    $cl=@($b|ForEach-Object{[double]$_.c}); $lo=@($b|ForEach-Object{[double]$_.l})
    $in=$false;$hd=0;$e=0
    for($i=201;$i -lt $cl.Count;$i++){
      if($in){
        $hd++
        $exited=$false
        if($stopPct -gt 0 -and $lo[$i] -le $e*(1-$stopPct)){ $all+=(-$stopPct); $in=$false; $exited=$true }
        if(-not $exited -and $profitTgt -gt 0 -and $cl[$i] -ge $e*(1+$profitTgt)){ $all+=$profitTgt; $in=$false; $exited=$true }
        if(-not $exited -and $firstUp -and $cl[$i] -gt $cl[$i-1]){ $all+=(($cl[$i]-$e)/$e); $in=$false; $exited=$true }
        if(-not $exited -and ((RsiN $cl $i 2) -ge $exitRsi -or $hd -ge $maxHold)){ $all+=(($cl[$i]-$e)/$e); $in=$false }
      }
      else{
        $sma=SmaN $cl $i 200; if($sma -eq $null -or $i -ge $cl.Count-1){ continue }
        $r2=(RsiN $cl $i 2)+(RsiN $cl ($i-1) 2)
        if($cl[$i] -gt $sma -and $r2 -lt 35){ $in=$true;$hd=0;$e=$cl[$i] }
      }
    }
  }
  if($all.Count -eq 0){ "$name : none"; return }
  $w=@($all|Where-Object{$_ -gt 0}).Count
  $m=($all|Measure-Object -Average).Average
  $sd=[math]::Sqrt((($all|ForEach-Object{($_-$m)*($_-$m)})|Measure-Object -Sum).Sum/$all.Count)
  $sh=if($sd -gt 0){[math]::Round($m/$sd,3)}else{0}
  $worst=[math]::Round((($all|Measure-Object -Minimum).Minimum)*100,2)
  "{0,-36} trades {1,4}  win {2,5}%  avg {3,7}%  worst {4,7}%  edge/risk {5,6}" -f $name,$all.Count,[math]::Round($w/$all.Count*100,1),[math]::Round($m*100,3),$worst,$sh
}
"=== EXIT RULE SHOOTOUT (entry fixed) ==="
Test "CURRENT: RSI>=65 or 5d"            65 5   0     0     $false
"--- vary the RSI exit threshold ---"
Test "RSI>=50 or 5d (exit sooner)"       50 5   0     0     $false
Test "RSI>=80 or 5d (hold longer)"       80 5   0     0     $false
"--- vary max hold ---"
Test "RSI>=65 or 3d"                     65 3   0     0     $false
Test "RSI>=65 or 10d"                    65 10  0     0     $false
"--- simple alternatives ---"
Test "first UP close"                    65 5   0     0     $true
Test "profit target +3%"                 65 5   0.03  0     $false
Test "profit target +5%"                 65 5   0.05  0     $false
"--- add a hard stop-loss ---"
Test "RSI>=65 or 5d + 5% stop"           65 5   0     0.05  $false
Test "RSI>=65 or 5d + 8% stop"           65 5   0     0.08  $false
Test "RSI>=65 or 5d + 12% stop (live)"   65 5   0     0.12  $false

