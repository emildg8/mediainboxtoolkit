#requires -Version 5.1
<#
.SYNOPSIS
  In-place: MediaInboxToolkit moves into Sort\_Workspace\*, then SeriesToolkit Batch on series/cartoons/animeSeries roots.
.NOTES
  ASCII-only paths under _Workspace avoid OEM codepage parse errors in ps1.
  Does not move to main library (Video\Serialy etc.) - only under Sort.
#>
[CmdletBinding()]
param(
    [string]$SortRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [string]$PolicyPath = '',
    [ValidateSet('Fast', 'Balanced', 'Full')]
    [string]$SeriesExecutionProfile = 'Balanced',
    [switch]$DryRun,
    [switch]$SkipMediaInbox,
    [switch]$SkipSeriesToolkit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mitRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $mitRoot 'sort-inbox.workspace-inside-sort.json'
}
if (-not (Test-Path -LiteralPath $PolicyPath)) {
    throw "Policy not found: $PolicyPath"
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
$transcript = Join-Path $logDir ("organize-sort-inplace-$stamp.log")
Start-Transcript -Path $transcript -Force
try {
    Write-Host "=== Organize-SortInPlace $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') ==="
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
        $ws = Join-Path $SortRoot '_Workspace'
        foreach ($sub in @('series', 'cartoons', 'animeSeries')) {
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
    Write-Host "Movies stay under _Workspace\\movies (SeriesToolkit batch not run there)."
    Write-Host "Related TV movie into show folder: not automated (needs TMDB link rules)."
    Write-Host "NFO/posters: not in Fetch-VideoMetadata; use Jellyfin or a future exporter."
}
finally {
    try { Stop-Transcript } catch { }
}
