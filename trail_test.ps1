# Would a TRAILING STOP have saved the MU trade (+$275 -> -$501)?
# Adds a trailing stop / breakeven-stop to the dip-buyer and measures the effect on 5yr of trades.
$ErrorActionPreference="Stop"
$k=$env:APCA_API_KEY_ID; $s=$env:APCA_API_SECRET_KEY; if(-not $k){ foreach($l in (Get-Content (Join-Path $PSScriptRoot "..\.env"))){ if($l -match "^\s*APCA_API_KEY_ID\s*=\s*(.+)$"){$k=$Matches[1].Trim()}; if($l -match "^\s*APCA_API_SECRET_KEY\s*=\s*(.+)$"){$s=$Matches[1].Trim()} } }; $h=@{ "APCA-API-KEY-ID"=$k; "APCA-API-SECRET-KEY"=$s }
$start="2020-06-01"
function Bars($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); ,@($all) }
function RsiN($cl,$i,$p){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $dd=$cl[$j]-$cl[$j-1]; if($dd -gt 0){$g+=$dd}else{$l+=-$dd} }; $al=$l/$p; if($al -eq 0){return 100}; 100-100/(1+($g/$p)/$al) }
function SmaN($cl,$i,$p){ if($i -lt $p-1){return $null}; $s=0.0; for($j=$i-$p+1;$j -le $i;$j++){$s+=$cl[$j]}; $s/$p }
$UNI=@("NVDA","MU","HOOD","GE","LRCX","PLTR","AMAT","META","AMD","AVGO","INTC","GOOGL")
$BK=@{}; "loading..."
foreach($s in $UNI){ try{ $b=Bars $s; if($b.Count -ge 260){ $BK[$s]=$b } }catch{} }
# trailPct: trail below the high-water mark (0=off). beEven: move stop to entry once up this % (0=off).
function Test($name,$trailPct,$beEven){
  $all=@()
  foreach($s in $BK.Keys){
    $b=$BK[$s]
    $cl=@($b|ForEach-Object{[double]$_.c}); $hi=@($b|ForEach-Object{[double]$_.h}); $lo=@($b|ForEach-Object{[double]$_.l})
    $in=$false;$hd=0;$e=0;$hw=0;$stop=0
    for($i=201;$i -lt $cl.Count;$i++){
      if($in){
        $hd++
        if($hi[$i] -gt $hw){ $hw=$hi[$i] }
        # raise the stop (never lower it)
        if($trailPct -gt 0){ $ns=$hw*(1-$trailPct); if($ns -gt $stop){ $stop=$ns } }
        if($beEven -gt 0 -and $hw -ge $e*(1+$beEven) -and $e -gt $stop){ $stop=$e }
        $exited=$false
        if($stop -gt 0 -and $lo[$i] -le $stop){ $all+=(($stop-$e)/$e); $in=$false; $exited=$true }
        if(-not $exited -and $lo[$i] -le $e*0.88){ $all+=(-0.12); $in=$false; $exited=$true }   # -12% disaster
        if(-not $exited -and ((RsiN $cl $i 2) -ge 65 -or $hd -ge 10)){ $all+=(($cl[$i]-$e)/$e); $in=$false }
      }
      else{
        $sma=SmaN $cl $i 200; if($sma -eq $null -or $i -ge $cl.Count-1){ continue }
        $r2=(RsiN $cl $i 2)+(RsiN $cl ($i-1) 2)
        if($cl[$i] -gt $sma -and $r2 -lt 35){ $in=$true;$hd=0;$e=$cl[$i];$hw=$cl[$i];$stop=0 }
      }
    }
  }
  if($all.Count -eq 0){ "$name : none"; return }
  $w=@($all|Where-Object{$_ -gt 0}).Count
  $m=($all|Measure-Object -Average).Average
  $worst=[math]::Round((($all|Measure-Object -Minimum).Minimum)*100,2)
  # how often did a winner turn into a loser? (proxy: losses worse than -3%)
  $bigLoss=@($all|Where-Object{$_ -lt -0.05}).Count
  "{0,-40} trades {1,4}  win {2,5}%  avg {3,7}%  worst {4,7}%  losses>5% {5,4}" -f $name,$all.Count,[math]::Round($w/$all.Count*100,1),[math]::Round($m*100,3),$worst,$bigLoss
}
"=== does a TRAILING STOP help the dip-buyer? ==="
Test "CURRENT: no trail, -12% disaster only"   0      0
"--- trailing stops ---"
Test "trail 3% below high"                     0.03   0
Test "trail 5% below high"                     0.05   0
Test "trail 8% below high"                     0.08   0
"--- breakeven stop (protect once in profit) ---"
Test "move stop to breakeven once +2%"         0      0.02
Test "move stop to breakeven once +4%"         0      0.04
Test "move stop to breakeven once +6%"         0      0.06
"--- combined ---"
Test "trail 8% + breakeven at +4%"             0.08   0.04

