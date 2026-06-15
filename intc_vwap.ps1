# INTC VWAP mean-reversion day-trader (Alpaca paper) - STATELESS, cloud + local.
# Entry: rest a BRACKET buy near VWAP (institutions' fair-value support) on a pullback.
#   - Volume/candle gate: skip arming if the last bar is a big RED candle on heavy volume
#     (falling knife) so we don't buy into an accelerating selloff.
# Exit (attached, broker-side OCO so it survives laptop-off):
#   - Take-profit: +$TARGET
#   - Stop-loss : below the recent swing low (capped to a max $ risk)
$ErrorActionPreference = "Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }

$SYM      = "INTC"
$BUDGET   = 10000.0   # ~$ to deploy
$TARGET   = 1.50      # profit per share
$MAX_RISK = 1.75      # max $ per share we'll risk (stop cap)
$STOP_BUF = 0.10      # place stop this far below swing low

function Stamp($m){ Write-Host ("{0}  {1}" -f (Get-Date -Format 'u'), $m) }
function OpenOrders(){ @(Invoke-RestMethod -Uri "$base/v2/orders?status=open&symbols=$SYM&nested=true" -Headers $h) }
function CancelAll(){ foreach($o in (OpenOrders)){ try{ Invoke-RestMethod -Uri "$base/v2/orders/$($o.id)" -Method Delete -Headers $h | Out-Null }catch{} } }

# --- guards ---
$clock=Invoke-RestMethod -Uri "$base/v2/clock" -Headers $h
if(-not $clock.is_open){ Stamp "market closed."; exit 0 }
$asset=Invoke-RestMethod -Uri "$base/v2/assets/$SYM" -Headers $h
if(-not $asset.tradable){ Stamp "$SYM not tradable."; exit 0 }

# --- data / research ---
$start=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddT13:30:00Z")
$bars=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$SYM/bars?timeframe=5Min&start=$start&limit=80&feed=iex" -Headers $h).bars
$price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$SYM/trades/latest" -Headers $h).trade.p
if(-not $bars -or $bars.Count -lt 4){ Stamp "not enough bars yet."; exit 0 }

$cumPV=0.0;$cumV=0.0
foreach($b in $bars){ $tp=([double]$b.h+[double]$b.l+[double]$b.c)/3; $cumPV+=$tp*[double]$b.v; $cumV+=[double]$b.v }
$vwap=[math]::Round($cumPV/$cumV,2)
$recent=$bars[-6..-1]
$swingLow=([double[]]($recent|ForEach-Object{[double]$_.l})|Measure-Object -Minimum).Minimum
$avgVol=(($bars[-10..-1]|ForEach-Object{[double]$_.v})|Measure-Object -Average).Average
$lb=$bars[-1]; $lbRed=([double]$lb.c -lt [double]$lb.o); $lbBody=[math]::Abs([double]$lb.o-[double]$lb.c)
$avgBody=(($bars[-10..-1]|ForEach-Object{[math]::Abs([double]$_.o-[double]$_.c)})|Measure-Object -Average).Average
$fallingKnife = ($lbRed -and $lbBody -gt 1.3*$avgBody -and [double]$lb.v -gt 1.3*$avgVol)

# --- position ---
try{ $pos=Invoke-RestMethod -Uri "$base/v2/positions/$SYM" -Headers $h; $qty=[int]$pos.qty }catch{ $qty=0 }
Stamp "price=$price vwap=$vwap swingLow=$swingLow avgVol=$([math]::Round($avgVol)) lastBarRed=$lbRed fallingKnife=$fallingKnife pos=$qty"

if($qty -gt 0){
    Stamp "holding $qty - bracket take-profit/stop is managing the exit."
    exit 0
}

# FLAT: arm a bracket buy near VWAP, unless a falling-knife candle says wait
$existing = @(OpenOrders | Where-Object { $_.side -eq "buy" })
if($fallingKnife){ if($existing.Count){ CancelAll }; Stamp "falling-knife candle - standing aside, no entry."; exit 0 }
if($existing.Count -ge 1){ Stamp "buy bracket already resting @ $($existing[0].limit_price)."; exit 0 }

# entry just at/below VWAP (buy the pullback to fair value); never above current price
$entry = [math]::Round([math]::Min($vwap, $price - 0.05), 2)
$lot   = [int][math]::Floor($BUDGET / $entry)
$tp    = [math]::Round($entry + $TARGET, 2)
$stopP = [math]::Round([math]::Max($swingLow - $STOP_BUF, $entry - $MAX_RISK), 2)
if($stopP -ge $entry){ $stopP = [math]::Round($entry - $MAX_RISK,2) }

$body=@{ symbol=$SYM; qty="$lot"; side="buy"; type="limit"; time_in_force="day"; limit_price="$entry";
         order_class="bracket"; take_profit=@{ limit_price="$tp" }; stop_loss=@{ stop_price="$stopP" } } | ConvertTo-Json -Depth 5
try{
    Invoke-RestMethod -Uri "$base/v2/orders" -Method Post -Headers $h -Body $body -ContentType "application/json" | Out-Null
    $risk=[math]::Round(($entry-$stopP)*$lot,2); $rew=[math]::Round($TARGET*$lot,2)
    Stamp "BRACKET buy $lot @ $entry | take-profit $tp (+`$$rew) | stop $stopP (-`$$risk)"
}catch{ Stamp "order err: $($_.ErrorDetails.Message)" }
