# Morning screener: scans a watchlist and picks the best day-trade candidate for the day.
# Favors liquid, volatile-but-not-runaway names in a tradeable price band. Writes pick.json.
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }
$pickFile=Join-Path $PSScriptRoot "pick.json"

$watch="AMD","NVDA","AAPL","AMZN","INTC","PLTR","SOFI","F","BAC","MU","AAL","CCL","TSLA","NIO"
$dstart=(Get-Date).ToUniversalTime().AddDays(-7).ToString("yyyy-MM-ddT00:00:00Z")
$rows=@()
foreach($s in $watch){
  try{
    $d=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=$dstart&limit=5&feed=iex" -Headers $h).bars
    if(-not $d -or $d.Count -lt 2){ continue }
    $last=$d[-1]; $price=[double]$last.c
    if($price -lt 15 -or $price -gt 320){ continue }   # tradeable band for ~$10k / $1-3 moves
    $rngs=$d | ForEach-Object { ([double]$_.h-[double]$_.l)/[double]$_.o*100 }
    $atrPct=[math]::Round((($rngs|Measure-Object -Average).Average),2)
    $vol=[double]$last.v
    # score: want movement (atr%) AND liquidity (volume). 2-6% atr is the sweet spot for scalps.
    $atrScore = if($atrPct -ge 2 -and $atrPct -le 6){ $atrPct } elseif($atrPct -gt 6){ 6 - ($atrPct-6)*0.5 } else { $atrPct*0.6 }
    $score=[math]::Round($atrScore * [math]::Log10([math]::Max($vol,1)),2)
    $rows+=[pscustomobject]@{Sym=$s;Price=$price;AtrPct=$atrPct;VolM=[math]::Round($vol/1e6,1);Score=$score}
  }catch{}
}
$ranked=$rows | Sort-Object Score -Descending
$ranked | Format-Table -AutoSize | Out-String | Write-Host
$best=$ranked | Select-Object -First 1
if(-not $best){ Write-Host "no candidate found"; exit 0 }
$pick=[ordered]@{ date=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"); symbol=$best.Sym; price=$best.Price; atr_pct=$best.AtrPct; score=$best.Score; reason="highest liquidity*volatility score in tradeable band" }
$pick | ConvertTo-Json | Set-Content $pickFile
Write-Host "PICK: $($best.Sym) @ $($best.Price) (atr% $($best.AtrPct), score $($best.Score))"
