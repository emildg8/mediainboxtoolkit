#requires -Version 5.1
<#
.SYNOPSIS
  Готовит CSV для ручной разметки (колонки Human*) и HTML-отчёт.
.EXAMPLE
  .\Prepare-MediaInboxReviewForHuman.ps1 -CsvPath .\LOGS\sort-inbox-20260505-184719.review.auto-torrent.csv
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
    $OutCsvPath = Join-Path $dir ($name + '.for-human.csv')
}

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) { throw "CSV has no rows: $CsvPath" }

$humanCols = @('HumanOverride', 'HumanComment', 'HumanDestOverride')
$baseOrder = @(
    'HumanOverride', 'HumanComment', 'HumanDestOverride',
    'Decision', 'DecisionNote', 'AutoRule',
    'DestRootKey', 'Confidence', 'Kind', 'ContentKindGuess', 'ContentKindConfidence', 'ContentKindReason',
    'SourceFullPath', 'DestFullPath', 'Notes', 'DryRun'
)

$allNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $rows) {
    foreach ($p in $r.PSObject.Properties) { [void]$allNames.Add($p.Name) }
}
foreach ($h in $humanCols) { [void]$allNames.Add($h) }

$orderedNames = [System.Collections.Generic.List[string]]::new()
foreach ($n in $baseOrder) {
    if ($allNames.Contains($n)) { [void]$orderedNames.Add($n) }
}
foreach ($n in ($allNames | Sort-Object)) {
    if (-not $orderedNames.Contains($n)) { [void]$orderedNames.Add($n) }
}

$out = foreach ($r in $rows) {
    $o = [ordered]@{}
    foreach ($n in $orderedNames) {
        if ($r.PSObject.Properties.Name -contains $n) {
            $o[$n] = [string]$r.$n
        }
        elseif ($humanCols -contains $n) {
            $o[$n] = ''
        }
        else {
            $o[$n] = ''
        }
    }
    [pscustomobject]$o
}

$out | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Encoding UTF8

$htmlPs1 = Join-Path $PSScriptRoot 'Export-MediaInboxReviewHtml.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $htmlPs1 -CsvPath $OutCsvPath

Write-Host "For-human CSV: $OutCsvPath"
Write-Host "Open the matching .html in a browser (colored REVIEW / APPLY / SKIP)."
