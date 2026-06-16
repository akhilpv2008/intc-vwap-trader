# Daily track record for the autonomous trader. Logs account P&L + the day's picked symbol
# and its realized fills, plus running cumulative + win-rate. Appends to pnl_history.csv.
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }
$csv=Join-Path $PSScriptRoot "pnl_history.csv"
$pickFile=Join-Path $PSScriptRoot "pick.json"
$today=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$sym = if(Test-Path $pickFile){ (Get-Content $pickFile|ConvertFrom-Json).symbol } else { "" }

$acct=Invoke-RestMethod -Uri "$base/v2/account" -Headers $h
$dayPL=[math]::Round([double]$acct.equity-[double]$acct.last_equity,2)
$acts=Invoke-RestMethod -Uri "$base/v2/account/activities/FILL?date=$today" -Headers $h
$f=@($acts | Where-Object { $_.symbol -eq $sym })
$buy=0.0;$sell=0.0;$nb=0;$ns=0
foreach($x in $f){ $v=[double]$x.qty*[double]$x.price; if($x.side -eq "buy"){$buy+=$v;$nb++}else{$sell+=$v;$ns++} }
$symPL=[math]::Round($sell-$buy,2); $rt=[math]::Min($nb,$ns)
$row="{0},{1},{2},{3},{4},{5},{6}" -f $today,$sym,$acct.equity,$dayPL,$rt,$symPL,([math]::Round([double]$acct.equity-10000,2))
if(-not (Test-Path $csv)){ Set-Content $csv "date,symbol,equity,account_day_pl,round_trips,symbol_cash_pl,cumulative_vs_10k" }
$ex=Get-Content $csv
if(($ex|Select-String "^$today,").Count -eq 0){ Add-Content $csv $row; Write-Host "RECORDED $row" }
else { Set-Content $csv ($ex|ForEach-Object{ if($_ -match "^$today,"){$row}else{$_} }); Write-Host "UPDATED $row" }
