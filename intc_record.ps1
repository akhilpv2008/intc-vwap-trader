# Appends one row per trading day to pnl_history.csv -> track record for the INTC strategy.
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }
$SYM="INTC"; $csv=Join-Path $PSScriptRoot "pnl_history.csv"
$today=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")

$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[math]::Round([double]$acct.equity-[double]$acct.last_equity,2)
$acts=Invoke-RestMethod -Uri "$base/v2/account/activities/FILL?date=$today" -Headers $h
$f=@($acts | Where-Object { $_.symbol -eq $SYM })
$buy=0.0;$sell=0.0;$nb=0;$ns=0
foreach($x in $f){ $v=[double]$x.qty*[double]$x.price; if($x.side -eq "buy"){$buy+=$v;$nb++}else{$sell+=$v;$ns++} }
try{ $pos=Invoke-RestMethod -Uri "$base/v2/positions/$SYM" -Headers $h; $oq=[int]$pos.qty; $ou=[double]$pos.unrealized_pl }catch{ $oq=0;$ou=0 }
$rt=[math]::Min($nb,$ns)
$row="{0},{1},{2},{3},{4},{5},{6},{7},{8}" -f $today,$acct.equity,$dayPL,$f.Count,$nb,$ns,$rt,[math]::Round($sell-$buy,2),$oq
if(-not (Test-Path $csv)){ Set-Content $csv "date,account_equity,account_day_pl,intc_fills,buys,sells,round_trips,intc_cash_pl,open_qty" }
$ex=Get-Content $csv
if(($ex | Select-String "^$today,").Count -eq 0){ Add-Content $csv $row; Write-Host "RECORDED $row" }
else { Set-Content $csv ($ex | ForEach-Object { if($_ -match "^$today,"){$row}else{$_} }); Write-Host "UPDATED $row" }
