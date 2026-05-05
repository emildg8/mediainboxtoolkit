#requires -Version 5.1
<#
.SYNOPSIS
  Создаёт копию dryrun CSV для ручной разметки (Decision / DecisionNote).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$OutCsvPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CsvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)
if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }

if ([string]::IsNullOrWhiteSpace($OutCsvPath)) {
    $dir = Split-Path -Parent $CsvPath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $OutCsvPath = Join-Path $dir ($name + '.review.csv')
}

$rows = @(Import-Csv -LiteralPath $CsvPath)
$out = foreach ($r in $rows) {
    $conf = 0
    try { $conf = [int]$r.Confidence } catch { $conf = 0 }
    $defaultDecision = if (($r.DestRootKey -ne 'review') -and $conf -ge 70) { 'APPLY' } else { 'REVIEW' }
    [pscustomobject]@{
        HumanOverride         = ''
        HumanComment          = ''
        HumanDestOverride     = ''
        Decision              = $defaultDecision
        DecisionNote          = ''
        SourceFullPath        = [string]$r.SourceFullPath
        DestFullPath          = [string]$r.DestFullPath
        Kind                  = [string]$r.Kind
        ContentKindGuess      = [string]$r.ContentKindGuess
        ContentKindConfidence = [string]$r.ContentKindConfidence
        ContentKindReason     = [string]$r.ContentKindReason
        DestRootKey           = [string]$r.DestRootKey
        Confidence            = [string]$r.Confidence
        Notes                 = [string]$r.Notes
        DryRun                = [string]$r.DryRun
    }
}

$out | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Review CSV: $OutCsvPath"
Write-Host "Rows: $($out.Count)"
