#requires -Version 5.1
<#
.SYNOPSIS
  Краткая сводка по размеченному CSV (APPLY/SKIP/REVIEW) для последующего ручного разбора.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [int]$Top = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CsvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)
if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }
$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) {
    Write-Host "CSV has no rows: $CsvPath"
    return
}
if (-not ($rows[0].PSObject.Properties.Name -contains 'Decision')) {
    throw 'CSV missing Decision column (expected APPLY/SKIP/REVIEW).'
}

$norm = {
    param($v)
    if ([string]::IsNullOrWhiteSpace([string]$v)) { return 'REVIEW' }
    $u = ([string]$v).Trim().ToUpperInvariant()
    if ($u -in @('APPLY', 'SKIP', 'REVIEW')) { return $u }
    return 'REVIEW'
}

$withDecision = @(
    foreach ($r in $rows) {
        [pscustomobject]@{
            Decision            = (& $norm $r.Decision)
            DestRootKey         = [string]$r.DestRootKey
            ContentKindGuess    = [string]$r.ContentKindGuess
            ContentKindReason   = [string]$r.ContentKindReason
            Confidence          = [string]$r.Confidence
            SourceFullPath      = [string]$r.SourceFullPath
            DestFullPath        = [string]$r.DestFullPath
            Notes               = [string]$r.Notes
            DecisionNote        = if ($r.PSObject.Properties.Name -contains 'DecisionNote') { [string]$r.DecisionNote } else { '' }
        }
    }
)

Write-Host "CSV: $CsvPath"
Write-Host "Rows: $($withDecision.Count)"
Write-Host ""
Write-Host "By Decision:"
$withDecision | Group-Object Decision | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ("  {0}: {1}" -f $_.Name, $_.Count)
}

Write-Host ""
Write-Host "Top REVIEW by DestRootKey:"
$withDecision |
    Where-Object { $_.Decision -eq 'REVIEW' } |
    Group-Object DestRootKey | Sort-Object Count -Descending | Select-Object -First $Top |
    ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Name, $_.Count) }

Write-Host ""
Write-Host "Top REVIEW by ContentKindReason:"
$withDecision |
    Where-Object { $_.Decision -eq 'REVIEW' } |
    Group-Object ContentKindReason | Sort-Object Count -Descending | Select-Object -First $Top |
    ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Name, $_.Count) }
