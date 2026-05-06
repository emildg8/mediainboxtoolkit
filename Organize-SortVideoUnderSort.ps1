#requires -Version 5.1
<#
.SYNOPSIS
  In-place: MediaInboxToolkit переносит в Sort\Video\*, затем SeriesToolkit Batch по series/cartoons/animeSeries.
.NOTES
  Подпапки под Sort\Video для SeriesToolkit читаются из политики: folders.workspaceSeriesToolkitSubfolders (иначе series, cartoons, animeSeries).
#>
[CmdletBinding()]
param(
    [string]$SortRoot = '',
    [string]$PolicyPath = '',
    [ValidateSet('Fast', 'Balanced', 'Full')]
    [string]$SeriesExecutionProfile = 'Balanced',
    [switch]$DryRun,
    [switch]$SkipMediaInbox,
    [switch]$SkipSeriesToolkit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SortRoot)) {
    $SortRoot = [Environment]::GetEnvironmentVariable('MIT_INBOX_ROOT', 'Process')
}
if ([string]::IsNullOrWhiteSpace($SortRoot)) {
    $SortRoot = [Environment]::GetEnvironmentVariable('MIT_INBOX_ROOT', 'User')
}
if ([string]::IsNullOrWhiteSpace($SortRoot)) {
    $SortRoot = '\\NAS\media\Video\Sort'
}

$mitRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $mitRoot 'sort-inbox.video-under-sort.example.json'
}
if (-not (Test-Path -LiteralPath $PolicyPath)) {
    throw "Policy not found: $PolicyPath"
}

$polObj = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$seriesToolkitSubs = @('series', 'cartoons', 'animeSeries')
if ($polObj.PSObject.Properties.Name -contains 'folders' -and $null -ne $polObj.folders) {
    $fd = $polObj.folders
    if ($fd.PSObject.Properties.Name -contains 'workspaceSeriesToolkitSubfolders' -and $null -ne $fd.workspaceSeriesToolkitSubfolders) {
        $arr = @($fd.workspaceSeriesToolkitSubfolders | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($arr.Count -ge 1) { $seriesToolkitSubs = $arr }
    }
}

$stRoot = Join-Path (Split-Path -Parent $mitRoot) 'SeriesToolkit'
$stLauncher = Join-Path $stRoot 'SeriesToolkit.ps1'
if (-not (Test-Path -LiteralPath $stLauncher)) {
    throw "SeriesToolkit.ps1 not found: $stLauncher"
}
$logDir = Join-Path $mitRoot 'LOGS'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir ("organize-sort-video-under-sort-$stamp.log")
Start-Transcript -Path $transcript -Force
try {
    Write-Host "=== Organize-SortVideoUnderSort $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') ==="
    Write-Host "SortRoot: $SortRoot"
    Write-Host "DryRun: $DryRun"

    if (-not $SkipMediaInbox) {
        Write-Host ""
        Write-Host "--- MediaInboxToolkit ---"
        $mit = Join-Path $mitRoot 'MediaInboxToolkit.ps1'
        $ma = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $mit,
            '-PolicyPath', $PolicyPath,
            '-InboxPath', $SortRoot,
            '-UseTmdb',
            '-SkipAutoVersion',
            '-SkipAutoSync'
        )
        if ($DryRun) { $ma += '-DryRun' }
        else { $ma += '-Apply' }
        & powershell.exe @ma
    }

    if (-not $SkipSeriesToolkit) {
        $ws = Join-Path $SortRoot 'Video'
        foreach ($sub in $seriesToolkitSubs) {
            $rp = Join-Path $ws $sub
            if (-not (Test-Path -LiteralPath $rp)) {
                Write-Host "[SeriesToolkit] skip missing: $rp"
                continue
            }
            $childDirs = @(Get-ChildItem -LiteralPath $rp -Directory -ErrorAction SilentlyContinue)
            if ($childDirs.Count -eq 0) {
                Write-Host "[SeriesToolkit] skip empty: $rp"
                continue
            }
            Write-Host ""
            Write-Host "--- SeriesToolkit RootPath=$rp ($($childDirs.Count) roots) ---"
            $sa = @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $stLauncher,
                '-Mode', 'Batch',
                '-RootPath', $rp,
                '-UseTmdb',
                '-ExecutionProfile', $SeriesExecutionProfile,
                '-SkipAutoVersion',
                '-SkipAutoSync'
            )
            if ($DryRun) { $sa += '-DryRun' }
            else { $sa += '-Apply' }
            & powershell.exe @sa
        }
    }

    Write-Host ""
    Write-Host "=== Done. Transcript: $transcript ==="
    Write-Host "Фильмы остаются под корнем movies (SeriesToolkit по ним batch не гоняется)."
}
finally {
    try { Stop-Transcript } catch { }
}
