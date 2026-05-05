#requires -Version 5.1
<#
.SYNOPSIS
  Ждёт появления нового sort-inbox-*.csv в LOGS (например после долгого DryRun) и печатает путь.
.EXAMPLE
  .\Watch-MediaInboxToolkitCsv.ps1 -After ([datetime]::UtcNow)
#>
[CmdletBinding()]
param(
    [datetime]$After = [datetime]::MinValue,
    [string]$LogDirectory = '',
    [int]$PollSeconds = 15,
    [int]$TimeoutMinutes = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path $PSScriptRoot 'LOGS'
}
if (-not (Test-Path -LiteralPath $LogDirectory)) {
    throw "LOGS not found: $LogDirectory"
}

if ($After -eq [datetime]::MinValue) {
    $After = Get-Date
}
$afterUtc = $After.ToUniversalTime()

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ((Get-Date) -lt $deadline) {
    $latest = Get-ChildItem -LiteralPath $LogDirectory -Filter 'sort-inbox-*.csv' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -ne $latest -and $latest.LastWriteTimeUtc -gt $afterUtc) {
        Write-Host "Готово: $($latest.FullName)  (размер $($latest.Length) байт, UTC $($latest.LastWriteTimeUtc))"
        return $latest.FullName
    }
    Start-Sleep -Seconds $PollSeconds
}

Write-Warning "Таймаут ${TimeoutMinutes} мин — нового CSV после $afterUtc не появилось."
return $null
