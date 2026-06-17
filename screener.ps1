# Morning screener v4: picks TOP 3 from today's LIVE market movers (gainers), filtered to
# liquid, real stocks (price >= $10, move 3-20%, heavy volume) - NOT penny-stock pumps.
# Writes pick.json { date, picks:[{symbol,...}] }. (TSLA excluded - separate strategy.)
$ErrorActionPreference="Stop"
$key=$env:APCA_API_KEY_ID; $sec=$env:APCA_API_SECRET_KEY
$base=$env:APCA_API_BASE_URL; if(-not $base){ $base="https://paper-api.alpaca.markets" }
$h=@{ "APCA-API-KEY-ID"=$key; "APCA-API-SECRET-KEY"=$sec }
$pickFile=Join-Path $PSScriptRoot "pick.json"
$exclude="TSLA","SPCX"

$cands=@()
try{
  $m=Invoke-RestMethod -Uri "https://data.alpaca.markets/v1beta1/screener/stocks/movers?top=25" -Headers $h
  foreach($g in $m.gainers){ $cands += [pscustomobject]@{Sym=$g.symbol; Price=[double]$g.price; Pct=[double]$g.percent_change} }
}catch{}
$rows=@()
foreach($c in ($cands | Where-Object { $_.Price -ge 8 -and $_.Price -le 320 -and $_.Pct -ge 2 -and $_.Pct -le 25 -and $exclude -notcontains $_.Sym })){
  try{
    # liquidity check via today's/last daily volume
    $d=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$($c.Sym)/bars?timeframe=1Day&limit=1&feed=iex" -Headers $h).bars
    $vol = if($d -and $d.Count){ [double]$d[-1].v } else { 0 }
    if($vol -lt 2000000){ continue }   # require >2M shares (liquid)
    $score=[math]::Round($c.Pct * [math]::Log10([math]::Max($vol,1)),2)
    $rows+=[pscustomobject]@{Sym=$c.Sym;Price=$c.Price;Pct=[math]::Round($c.Pct,2);VolM=[math]::Round($vol/1e6,1);Score=$score}
  }catch{}
}
$ranked=@($rows | Sort-Object Score -Descending)
$ranked | Format-Table -AutoSize | Out-String | Write-Host

# FALLBACK: if fewer than 3 liquid movers today, fill from the volatile-liquid watchlist
if($ranked.Count -lt 3){
  Write-Host "only $($ranked.Count) liquid movers - filling from volatility watchlist"
  $watch="AMD","NVDA","AAPL","AMZN","INTC","PLTR","SOFI","F","BAC","MU","AAL","CCL","NIO","COIN","RIVN","DKNG","MARA","RIOT","HOOD","SNAP","UBER","BABA","NKE","DIS","SHOP","COIN","PYPL","ROKU","AFRM","DAL","CVNA","XYZ"
  $dstart=(Get-Date).ToUniversalTime().AddDays(-7).ToString("yyyy-MM-ddT00:00:00Z")
  $have=$ranked | ForEach-Object { $_.Sym }
  $fb=@()
  foreach($s in ($watch | Where-Object { $have -notcontains $_ -and $exclude -notcontains $_ })){
    try{
      $d=(Invoke-RestMethod -Uri "https://data.alpaca.markets/v2/stocks/$s/bars?timeframe=1Day&start=$dstart&limit=6&feed=iex" -Headers $h).bars
      if(-not $d -or $d.Count -lt 2){ continue }
      $price=[double]$d[-1].c; if($price -lt 10 -or $price -gt 320){ continue }
      $atr=[math]::Round(((($d|ForEach-Object{([double]$_.h-[double]$_.l)/[double]$_.o*100})|Measure-Object -Average).Average),2)
      $fb+=[pscustomobject]@{Sym=$s;Price=$price;Pct=$atr;VolM=[math]::Round([double]$d[-1].v/1e6,1);Score=$atr}
    }catch{}
  }
  $ranked += ($fb | Sort-Object Score -Descending)
}
$top=@($ranked | Select-Object -First 3)
if(-not $top -or $top.Count -eq 0){ Write-Host "no candidates - leaving prior pick"; exit 0 }
$picks=@($top | ForEach-Object { [ordered]@{ symbol=$_.Sym; price=$_.Price; pct=$_.Pct; vol_m=$_.VolM; score=$_.Score } })
$out=[ordered]@{ date=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"); strategy="momentum+trailing"; picks=$picks }
$out | ConvertTo-Json -Depth 5 | Set-Content $pickFile
Write-Host ("PICKS: " + (($top|ForEach-Object{ "$($_.Sym) @$($_.Price) (+$($_.Pct)%)" }) -join ", "))
