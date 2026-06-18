# Guaranteed end-of-day flatten — closes ALL positions + cancels ALL orders in the account.
# Runs as its own once-daily cloud job (reliable) so NO overnight holds, even laptop-off.
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }
function Stamp($m){ Write-Host ("{0}  FLATTEN: {1}" -f (Get-Date -Format 'u'),$m) }

$clock=Invoke-RestMethod -Uri "$base/v2/clock" -Headers $h
# close everything: cancel all open orders, then liquidate all positions at market
try{ Invoke-RestMethod -Uri "$base/v2/orders" -Method Delete -Headers $h | Out-Null; Stamp "cancelled all open orders" }catch{ Stamp "cancel-all err: $($_.ErrorDetails.Message)" }
Start-Sleep -Seconds 2
$pos=@(Invoke-RestMethod -Uri "$base/v2/positions" -Headers $h)
if($pos.Count -eq 0){ Stamp "already flat - nothing to close"; exit 0 }
foreach($p in $pos){
  try{ Invoke-RestMethod -Uri "$base/v2/positions/$($p.symbol)" -Method Delete -Headers $h | Out-Null; Stamp "closed $($p.qty) $($p.symbol)" }
  catch{ Stamp "close err $($p.symbol): $($_.ErrorDetails.Message)" }
}
Start-Sleep -Seconds 2
$left=@(Invoke-RestMethod -Uri "$base/v2/positions" -Headers $h).Count
Stamp "done. positions remaining=$left"
