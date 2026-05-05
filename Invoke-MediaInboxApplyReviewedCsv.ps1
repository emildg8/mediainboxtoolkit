#requires -Version 5.1
<#
.SYNOPSIS
  Применяет перенос только по подтверждённым строкам CSV (после ручной разметки).
.DESCRIPTION
  В CSV должны быть колонки:
    - SourceFullPath
    - DestFullPath
    - Decision  (APPLY | SKIP | REVIEW)
    - DecisionNote (необязательно)

  Ручная правка (приоритетнее Decision):
    - HumanOverride — пусто или APPLY | SKIP | REVIEW
    - HumanDestOverride — полный путь назначения, если переопределяете DestFullPath
    - HumanComment — для себя, на перенос не влияет

  Переносятся только строки, у которых эффективное решение = APPLY.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$InboxRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CsvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)
if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not (Test-Path -LiteralPath $InboxRoot)) { throw "InboxRoot not found: $InboxRoot" }

$inboxNorm = $InboxRoot.TrimEnd('\')
$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) {
    Write-Host "CSV has no rows: $CsvPath"
    return
}

$required = @('SourceFullPath', 'DestFullPath', 'Decision')
foreach ($req in $required) {
    if (-not ($rows[0].PSObject.Properties.Name -contains $req)) {
        throw "CSV missing required column: $req"
    }
}

function Get-MitEffectiveDecision {
    param($Row)
    if ($Row.PSObject.Properties.Name -contains 'HumanOverride') {
        $h = ([string]$Row.HumanOverride).Trim().ToUpperInvariant()
        if ($h -in @('APPLY', 'SKIP', 'REVIEW')) { return $h }
    }
    $d = ([string]$Row.Decision).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($d)) { return 'REVIEW' }
    return $d
}

function Get-MitEffectiveDest {
    param($Row)
    if ($Row.PSObject.Properties.Name -contains 'HumanDestOverride') {
        $hd = ([string]$Row.HumanDestOverride).Trim()
        if (-not [string]::IsNullOrWhiteSpace($hd)) { return $hd }
    }
    return [string]$Row.DestFullPath
}

$toApply = @($rows | Where-Object { (Get-MitEffectiveDecision $_) -eq 'APPLY' })
$skip = @($rows | Where-Object { (Get-MitEffectiveDecision $_) -eq 'SKIP' })
$review = @($rows | Where-Object { (Get-MitEffectiveDecision $_) -eq 'REVIEW' })

$moved = 0
$failed = 0
$log = [System.Collections.Generic.List[object]]::new()

foreach ($r in $toApply) {
    $src = [string]$r.SourceFullPath
    $dst = Get-MitEffectiveDest $r
    if ([string]::IsNullOrWhiteSpace($src) -or [string]::IsNullOrWhiteSpace($dst)) {
        $failed++
        $log.Add([pscustomobject]@{ Decision = 'APPLY'; Status = 'FAIL'; Source = $src; Dest = $dst; Error = 'empty_source_or_dest' }) | Out-Null
        continue
    }

    # Safety: не трогаем файлы вне inbox
    if (($src.TrimEnd('\') -notlike "$inboxNorm*") -or ($dst.TrimEnd('\') -notlike "$inboxNorm*")) {
        $failed++
        $log.Add([pscustomobject]@{ Decision = 'APPLY'; Status = 'FAIL'; Source = $src; Dest = $dst; Error = 'path_outside_inbox' }) | Out-Null
        continue
    }
    if (-not (Test-Path -LiteralPath $src)) {
        $failed++
        $log.Add([pscustomobject]@{ Decision = 'APPLY'; Status = 'FAIL'; Source = $src; Dest = $dst; Error = 'source_missing' }) | Out-Null
        continue
    }
    try {
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            if (-not $WhatIf) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        }
        if ($WhatIf) {
            $log.Add([pscustomobject]@{ Decision = 'APPLY'; Status = 'WHATIF'; Source = $src; Dest = $dst; Error = '' }) | Out-Null
        } else {
            Move-Item -LiteralPath $src -Destination $dst -Force
            $moved++
            $log.Add([pscustomobject]@{ Decision = 'APPLY'; Status = 'MOVED'; Source = $src; Dest = $dst; Error = '' }) | Out-Null
        }
    } catch {
        $failed++
        $log.Add([pscustomobject]@{ Decision = 'APPLY'; Status = 'FAIL'; Source = $src; Dest = $dst; Error = $_.Exception.Message }) | Out-Null
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $PSScriptRoot 'LOGS'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$reportPath = Join-Path $logDir ("apply-reviewed-$stamp.csv")
$log | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

Write-Host "Reviewed CSV: $CsvPath"
Write-Host "APPLY rows: $($toApply.Count)  SKIP: $($skip.Count)  REVIEW/empty: $($review.Count)"
Write-Host "Moved: $moved  Failed: $failed  WhatIf: $WhatIf"
Write-Host "Report: $reportPath"
