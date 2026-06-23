# Screener (TQQQ/SQQQ directional mode): the universe is just the two Nasdaq 3x ETFs.
# The trader's VWAP+RSI+MACD gate then auto-picks whichever is trending UP today:
#   market rising -> TQQQ qualifies ; market falling -> SQQQ qualifies ; chop -> neither -> sit out.
# One clean directional call a day, profits both up and down days.
$out=[ordered]@{
  date=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
  strategy="tqqq-sqqq-directional"
  picks=@(
    [ordered]@{ symbol="TQQQ" },
    [ordered]@{ symbol="SQQQ" }
  )
}
$out | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PSScriptRoot "pick.json")
Write-Host "PICKS: TQQQ, SQQQ (directional - gate auto-selects the one trending up)"
