# Tune test: does the +$150 profit-lock help or hurt? 2% vs 3% trailing stop?
# Simulates the live intraday logic on 5-min bars (~45 days), TQQQ/SQQQ, $10k full-size per trade.
# Daily profit-lock: once realized day P&L >= target, no NEW entries that day (matches PROTECT MODE).
$ErrorActionPreference="Stop"
$h=@{ "APCA-API-KEY-ID"="PKRIYKPAOXT3WFBOYB76RQI2Y5"; "APCA-API-SECRET-KEY"="9YFAk7FovxgzsyokeZBwBrbjXDdkgo6wSUtA2bYQp1do" }
$start=(Get-Date).ToUniversalTime().AddDays(-45).ToString("yyyy-MM-dd")
$BOOK=10000.0
function Bars5($s){ $all=@();$pt=$null; do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=5Min&start=${start}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $h; $all+=$r.bars; $pt=$r.next_page_token }while($pt); $all }
function EmaArr($v,$p){ $k=2.0/($p+1); $o=@($v[0]); for($i=1;$i -lt $v.Count;$i++){ $o+=($v[$i]*$k+$o[$i-1]*(1-$k)) }; $o }
function RsiAt($c,$i,$p=14){ if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; return 100-100/(1+($g/$p)/$al) }
function BT($sym,$trail,$dayTarget){
  $b=Bars5 $sym; if($b.Count -lt 50){ return "${sym}: no data" }
  $c=@($b|ForEach-Object{[double]$_.c}); $e12=EmaArr $c 12;$e26=EmaArr $c 26;$macd=@();for($i=0;$i -lt $c.Count;$i++){$macd+=($e12[$i]-$e26[$i])};$sig=EmaArr $macd 9
  $rsi=@();for($i=0;$i -lt $c.Count;$i++){$rsi+=(RsiAt $c $i 14)}
  $inpos=$false;$entry=0;$hw=0;$stop=0;$curDay="";$pv=0;$vv=0;$w=0;$l=0;$dayPL=0.0;$tot=0.0;$peak=0.0;$maxdd=0.0;$trades=0
  for($i=1;$i -lt $b.Count;$i++){
    $day=$b[$i].t.Substring(0,10)
    if($day -ne $curDay){ if($inpos){$r=([double]$b[$i-1].c-$entry)/$entry;$pl=$r*$BOOK;$tot+=$pl;if($r -gt 0){$w++}else{$l++};$inpos=$false}; $curDay=$day;$pv=0;$vv=0;$dayPL=0.0 }
    $tp=([double]$b[$i].h+[double]$b[$i].l+[double]$b[$i].c)/3;$pv+=$tp*[double]$b[$i].v;$vv+=[double]$b[$i].v;$vwap=if($vv -gt 0){$pv/$vv}else{[double]$b[$i].c}
    $px=[double]$b[$i].c;$lo=[double]$b[$i].l;$isLast=($i -eq $b.Count-1 -or $b[$i+1].t.Substring(0,10) -ne $day)
    if($inpos){
      if($px -gt $hw){$hw=$px}; $ns=$hw*(1-$trail); if($ns -gt $stop){$stop=$ns}
      if($lo -le $stop){$r=($stop-$entry)/$entry;$pl=$r*$BOOK;$tot+=$pl;$dayPL+=$pl;if($r -gt 0){$w++}else{$l++};$inpos=$false}
      elseif($isLast){$r=($px-$entry)/$entry;$pl=$r*$BOOK;$tot+=$pl;$dayPL+=$pl;if($r -gt 0){$w++}else{$l++};$inpos=$false}
      if($tot -gt $peak){$peak=$tot}; $dd=$peak-$tot; if($dd -gt $maxdd){$maxdd=$dd}
    } else {
      $locked=($dayTarget -gt 0 -and $dayPL -ge $dayTarget)
      $bull=($px -gt [double]$b[$i].o);$rok=($rsi[$i] -gt 40 -and $rsi[$i] -lt 72 -and $rsi[$i] -ge $rsi[$i-1]);$mok=($macd[$i] -gt $sig[$i])
      if(-not $isLast -and -not $locked -and $px -gt $vwap -and $bull -and $rok -and $mok){$inpos=$true;$entry=$px;$hw=$px;$stop=$px*(1-0.025);$trades++}
    }
  }
  $n=$w+$l
  return [pscustomobject]@{Sym=$sym;Trades=$n;Win=[math]::Round($w/[math]::Max($n,1)*100,1);PL=[math]::Round($tot,0);MaxDD=[math]::Round($maxdd,0)}
}
function Show($label,$trail,$tgt){
  $sum=0
  foreach($s in "TQQQ","SQQQ"){ $r=BT $s $trail $tgt; if($r -is [string]){$r}else{ $sum+=$r.PL; "  {0,-5} {1,3} trades  win {2,5}%  P&L `${3,6}  maxDD `${4,5}" -f $r.Sym,$r.Trades,$r.Win,$r.PL,$r.MaxDD } }
  "  >>> $label COMBINED P&L: `$$sum`n"
}
"### 2% trail + `$150 daily profit-lock (CURRENT setup) ###"; Show "CURRENT (2% / lock 150)" 0.02 150
"### 2% trail + NO lock (trade all day) ###";               Show "2% / no lock" 0.02 0
"### 3% trail + `$150 lock ###";                             Show "3% / lock 150" 0.03 150
"### 3% trail + NO lock ###";                                Show "3% / no lock" 0.03 0
