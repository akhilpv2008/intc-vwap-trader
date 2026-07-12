# ============================================================================
#  DIP-BUYER (mean-reversion) - the strategy that actually tested profitable.
#  Runs ONCE per day near the close (~3:45pm ET). Holds 1-5 days (OVERNIGHT ok).
#
#  RULES (from backtest, 5yr: TQQQ +203% / Sharpe 0.86 / maxDD 22%, in cash ~80% of days):
#   ENTRY (near close):  RSI(2) < 10  AND  close > 200-day SMA   -> BUY (buy the dip in an uptrend)
#   EXIT  (near close):  RSI(2) >= 65  OR  held >= 5 trading days -> SELL
#   SAFETY: wide broker-side disaster stop (-12%) for tail risk only (durable, laptop-off safe).
#   Universe: scan QQQ + TQQQ, max ONE position; prefer TQQQ when both qualify (higher payoff).
#   Cash-only, no margin.
# ============================================================================
$ErrorActionPreference="Stop"
# --- creds: cloud uses env secrets; locally fall back to .env ---
$base=$env:APCA_API_BASE_URL; $kid=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
if(-not $kid){ $env_lines=Get-Content (Join-Path $PSScriptRoot "..\.env") | Where-Object { $_ -match '=' }
  $m=@{}; foreach($l in $env_lines){ $p=$l -split '=',2; if($p.Count -eq 2){ $m[$p[0].Trim()]=$p[1].Trim() } }
  $kid=$m["APCA_API_KEY_ID"]; $sec=$m["APCA_API_SECRET_KEY"]; $base=$m["APCA_API_BASE_URL"] }
if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$kid; "APCA-API-SECRET-KEY"=$sec }
$dh=@{ "APCA-API-KEY-ID"=$kid; "APCA-API-SECRET-KEY"=$sec }
# v2 (2026-07-12): individual-stock BASKET. 5yr backtest of this exact signal on these names:
# 68% win rate over 1,453 trades; NVDA +274%, AMD +168%, INTC +127%. (TSLA/SOFI/UNH tested NEGATIVE - excluded.)
$UNIVERSE=@("NVDA","AMD","INTC","HOOD","PLTR","META","MSFT","AMZN","GOOGL","AAPL","TQQQ")   # scan order = backtest strength
$MAX_POSITIONS=3              # basket: up to 3 concurrent dip positions (diversifies the falling-knife risk)
$DISASTER_STOP=0.12           # -12% broker-side tail stop (wide, rarely hit)
$MAX_HOLD_DAYS=5
function Stamp($m){ Write-Host "[$([DateTime]::UtcNow.ToString('HH:mm:ss'))] $m" }
function DailyCloses($s){
  $st=(Get-Date).ToUniversalTime().AddDays(-420).ToString("yyyy-MM-dd")
  $all=@();$pt=$null
  do{ $u="https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=${st}T00:00:00Z&limit=10000&feed=iex&adjustment=all"; if($pt){$u+="&page_token=$pt"}; $r=Invoke-RestMethod -Uri $u -Headers $dh; $all+=$r.bars; $pt=$r.next_page_token }while($pt)
  ,@($all)
}
function Rsi($c,$p){ $i=$c.Count-1; if($i -lt $p){return 50}; $g=0.0;$l=0.0; for($j=$i-$p+1;$j -le $i;$j++){ $d=$c[$j]-$c[$j-1]; if($d -gt 0){$g+=$d}else{$l+=-$d} }; $al=$l/$p; if($al -eq 0){return 100}; [math]::Round(100-100/(1+($g/$p)/$al),1) }
function Sma($c,$p){ if($c.Count -lt $p){return $null}; $s=0.0; for($j=$c.Count-$p;$j -lt $c.Count;$j++){$s+=$c[$j]}; $s/$p }
function Pos($s){ try{ Invoke-RestMethod -Uri "$base/v2/positions/$s" -Headers $h }catch{ $null } }
function HeldDays($s){
  try{ $o=@(Invoke-RestMethod -Uri "$base/v2/orders?status=all&symbols=$s&limit=30&direction=desc" -Headers $h)
    $lastBuy=$o | Where-Object { $_.side -eq "buy" -and [double]$_.filled_qty -gt 0 } | Select-Object -First 1
    if(-not $lastBuy){ return 0 }
    $d0=([datetime]$lastBuy.filled_at).Date; $d1=(Get-Date).Date; $n=0
    for($d=$d0; $d -lt $d1; $d=$d.AddDays(1)){ if($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday'){ $n++ } }
    $n
  }catch{ 0 }
}
function CancelOpen($s){ foreach($o in @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$s" -Headers $h)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h|Out-Null }catch{} } }

$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$cash=[double]$acct.cash
# MORNING SAFETY MODE: runs before 14:00 ET only verify/re-arm stops (backtest: morning entries are WORSE
# 65.7%/+0.74% vs close 69.2%/+0.77% - the bounce starts in the overnight gap). Decisions happen at ~3:45pm ET.
$etHour=[int]([DateTime]::UtcNow.AddHours(-4).Hour)
$morningMode=($etHour -lt 14)
Stamp "DIP-BUYER run. equity $([math]::Round([double]$acct.equity,2)) cash $([math]::Round($cash,2)) mode=$(if($morningMode){'MORNING-SAFETY (stops only)'}else{'DECISION'})"

# 1) MANAGE existing dip positions (exit check)
$heldCount=0
foreach($s in $UNIVERSE){
  $p=Pos $s; if(-not $p){ continue }
  $heldCount++
  $c=DailyCloses $s; $closes=@($c|ForEach-Object{[double]$_.c})
  $rsi=Rsi $closes 2; $held=HeldDays $s
  $upl=[math]::Round([double]$p.unrealized_pl,2)
  if((-not $morningMode) -and ($rsi -ge 65 -or $held -ge $MAX_HOLD_DAYS)){
    CancelOpen $s; Start-Sleep -Seconds 1
    try{ Invoke-RestMethod -Uri "$base/v2/positions/$s" -Method Delete -Headers $h | Out-Null; Stamp "EXIT $s (RSI2=$rsi, held=$held d) uPL=$upl" }
    catch{ Stamp "$s exit err $($_.Exception.Message)" }
  } else {
    Stamp "HOLD $s qty $($p.qty) (RSI2=$rsi, held=$held d, need RSI>=65 or 5d) uPL=$upl"
    # safety net: make sure a disaster stop is resting; re-arm if it vanished
    $hasStop=@(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$s" -Headers $h | Where-Object { $_.side -eq "sell" -and $_.type -eq "stop" }).Count -ge 1
    if(-not $hasStop){
      $entryPx=[double]$p.avg_entry_price; $stopPx=[math]::Round($entryPx*(1-$DISASTER_STOP),2)
      $sb=@{ symbol=$s; qty="$($p.qty)"; side="sell"; type="stop"; stop_price="$stopPx"; time_in_force="gtc" } | ConvertTo-Json
      try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $sb -ContentType "application/json"|Out-Null; Stamp "$s RE-ARMED missing disaster-stop @ $stopPx" }catch{ Stamp "$s re-arm stop err $($_.ErrorDetails.Message)" }
    }
  }
}
if($morningMode){ Stamp "morning safety run done (stops verified) - entry/exit decisions at 3:45pm"; exit 0 }
$slots=$MAX_POSITIONS-$heldCount
if($slots -le 0){ Stamp "basket full ($heldCount/$MAX_POSITIONS) - no new entries this run"; exit 0 }

# 2) SCAN for new dip-buys (fill free basket slots; capital split per slot)
$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h; $cash=[double]$acct.cash
$perSlot=[math]::Floor($cash/$slots*0.97)
foreach($s in $UNIVERSE){
  if($slots -le 0){ break }
  if(Pos $s){ continue }   # already hold this name
  $c=DailyCloses $s; $closes=@($c|ForEach-Object{[double]$_.c})
  if($closes.Count -lt 205){ Stamp "$s insufficient history"; continue }
  $rsi=Rsi $closes 2; $rsiY=Rsi ($closes[0..($closes.Count-2)]) 2; $cumRsi=$rsi+$rsiY
  $sma=Sma $closes 200; $px=$closes[-1]
  # v3 entry: CUMULATIVE RSI2 (today+yesterday) < 35 (shootout: 71.6% win / +0.87% per trade vs 69.2% / +0.77% for RSI2<10)
  $cond=($cumRsi -lt 35 -and $px -gt $sma)
  Stamp "$s scan: cumRSI2=$([math]::Round($cumRsi,1)) (today $rsi + yday $rsiY)  px=$([math]::Round($px,2))  200SMA=$([math]::Round($sma,2))  dipBuy=$cond"
  if($cond){
    $lot=[int][math]::Floor($perSlot/$px); if($lot -lt 1){ Stamp "$s not enough cash per slot"; continue }
    $body=@{ symbol=$s; qty="$lot"; side="buy"; type="market"; time_in_force="day" } | ConvertTo-Json
    try{
      $ord=Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $body -ContentType "application/json"
      Stamp "BUY $s $lot @ ~$([math]::Round($px,2)) (RSI2=$rsi dip in uptrend)"
      # wait for the buy to actually FILL before arming the stop (else it rejects for insufficient qty)
      $filled=$false
      for($try=1;$try -le 20;$try++){ Start-Sleep -Seconds 2; $chk=Pos $s; if($chk -and [int]$chk.qty -ge 1){ $filled=$true; break } }
      $stopPx=[math]::Round($px*(1-$DISASTER_STOP),2)
      $armed=$false
      for($try=1;$try -le 5 -and -not $armed;$try++){
        $sb=@{ symbol=$s; qty="$lot"; side="sell"; type="stop"; stop_price="$stopPx"; time_in_force="gtc" } | ConvertTo-Json
        try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $sb -ContentType "application/json"|Out-Null; $armed=$true; Stamp "$s disaster-stop set @ $stopPx (-12%)" }
        catch{ Stamp "$s stop attempt $try err $($_.ErrorDetails.Message)"; Start-Sleep -Seconds 3 }
      }
      if(-not $armed){ Stamp "$s WARNING: disaster stop NOT armed after retries - position UNPROTECTED, needs manual stop!" }
      $slots--   # slot consumed
    } catch { Stamp "$s buy err $($_.ErrorDetails.Message)" }
  }
}
Stamp "scan done. positions held: $($MAX_POSITIONS-$slots)/$MAX_POSITIONS"
