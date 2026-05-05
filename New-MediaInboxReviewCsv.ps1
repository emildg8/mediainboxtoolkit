#requires -Version 5.1
<#
.SYNOPSIS
  Создаёт копию dryrun CSV для ручной разметки (Decision / DecisionNote).
.DESCRIPTION
  По умолчанию APPLY только при Confidence >= 70. Для сериалов с уже собранным путём (в DestFullPath есть « - SxxEyy - ») можно снизить порог отдельно (по умолчанию 55), не трогая фильмы с низкой уверенностью.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$OutCsvPath = '',
    [int]$ApplyMinConfidence = 70,
    [int]$SeriesEpisodeStructuredMinConfidence = 55
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
    $destRoot = [string]$r.DestRootKey
    $destFull = [string]$r.DestFullPath
    $structuredSeries = ($destRoot -eq 'series') -and ($destFull -match ' - S\d{2}E\d{2} - ')
    $defaultDecision = 'REVIEW'
    if (($destRoot -ne 'review') -and ($conf -ge $ApplyMinConfidence)) {
        $defaultDecision = 'APPLY'
    }
    elseif (
        ($SeriesEpisodeStructuredMinConfidence -gt 0) -and
        ($destRoot -ne 'review') -and
        $structuredSeries -and
        ($conf -ge $SeriesEpisodeStructuredMinConfidence)
    ) {
        $defaultDecision = 'APPLY'
    }
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
