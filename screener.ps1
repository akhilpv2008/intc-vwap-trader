# Morning screener: scans a watchlist and picks the TOP 3 day-trade candidates.
# Score = recent volatility x liquidity, boosted if the stock is GAPPING today (in play).
# Writes pick.json { date, picks:[{symbol,...}x3] }. (TSLA excluded - separate strategy owns it.)
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }
$pickFile=Join-Path $PSScriptRoot "pick.json"

$watch="AMD","NVDA","AAPL","AMZN","INTC","PLTR","SOFI","F","BAC","MU","AAL","CCL","NIO","COIN","RIVN","DKNG"
$dstart=(Get-Date).ToUniversalTime().AddDays(-7).ToString("yyyy-MM-ddT00:00:00Z")
$rows=@()
foreach($s in $watch){
  try{
    $d=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=$dstart&limit=6&feed=iex" -Headers $h).bars
    if(-not $d -or $d.Count -lt 2){ continue }
    $prevClose=[double]$d[-1].c
    $price=[double](Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/trades/latest" -Headers $h).trade.p
    if($price -lt 15 -or $price -gt 320){ continue }
    $rngs=$d | ForEach-Object { ([double]$_.h-[double]$_.l)/[double]$_.o*100 }
    $atrPct=[math]::Round((($rngs|Measure-Object -Average).Average),2)
    $vol=[double]$d[-1].v
    $gapPct=[math]::Round([math]::Abs(($price-$prevClose)/$prevClose*100),2)   # how much it's moving today vs last close
    $atrScore = if($atrPct -ge 2 -and $atrPct -le 6){ $atrPct } elseif($atrPct -gt 6){ 6-($atrPct-6)*0.5 } else { $atrPct*0.6 }
    $score=[math]::Round($atrScore * [math]::Log10([math]::Max($vol,1)) * (1 + $gapPct*0.15), 2)  # gap boost = "in play today"
    $rows+=[pscustomobject]@{Sym=$s;Price=$price;AtrPct=$atrPct;GapPct=$gapPct;VolM=[math]::Round($vol/1e6,1);Score=$score}
  }catch{}
}
$ranked=$rows | Sort-Object Score -Descending
$ranked | Format-Table -AutoSize | Out-String | Write-Host
$top=$ranked | Select-Object -First 3
if(-not $top){ Write-Host "no candidates"; exit 0 }
$picks=@($top | ForEach-Object { [ordered]@{ symbol=$_.Sym; price=$_.Price; atr_pct=$_.AtrPct; gap_pct=$_.GapPct; score=$_.Score } })
$out=[ordered]@{ date=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"); picks=$picks }
$out | ConvertTo-Json -Depth 5 | Set-Content $pickFile
Write-Host ("PICKS: " + (($top|ForEach-Object{ "$($_.Sym)@$($_.Price)" }) -join ", "))
