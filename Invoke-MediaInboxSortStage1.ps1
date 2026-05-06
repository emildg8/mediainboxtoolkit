#requires -Version 5.1
<#
.SYNOPSIS
  Этап 1: создать скелет Video\… под Sort и DryRun MediaInboxToolkit (логи в LOGS\).
.PARAMETER Interactive
  После DryRun ждёт Enter перед выходом.
.PARAMETER SkeletonProfile
  Ascii (по умолчанию) или Cyrillic — выбор встроенной политики, если не задан -PolicyPath.
#>
[CmdletBinding()]
param(
    [string]$SortRoot = '',
    [string]$PolicyPath = '',
    [ValidateSet('Ascii', 'Cyrillic')]
    [string]$SkeletonProfile = 'Ascii',
    [switch]$Interactive,
    [switch]$SkipSkeleton
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
    if ($SkeletonProfile -eq 'Cyrillic') {
        $PolicyPath = Join-Path $mitRoot 'sort-inbox.video-under-sort.cyrillic.example.json'
    } else {
        $PolicyPath = Join-Path $mitRoot 'sort-inbox.video-under-sort.example.json'
    }
}

$skel = Join-Path $mitRoot 'New-MediaInboxDestinationSkeleton.ps1'
if (-not $SkipSkeleton) {
    Write-Host '--- Skeleton (destinations.*) ---'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $skel -PolicyPath $PolicyPath
}

if (-not (Test-Path -LiteralPath $SortRoot)) {
    throw "SortRoot not reachable: $SortRoot (skeleton may still be OK if nasShareRoot differs)."
}

Write-Host '--- MediaInboxToolkit DryRun ---'
$mit = Join-Path $mitRoot 'MediaInboxToolkit.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mit `
    -PolicyPath $PolicyPath -InboxPath $SortRoot -UseTmdb -DryRun -SkipAutoVersion -SkipAutoSync

Write-Host 'Check LOGS\ for latest sort-inbox-*.csv and summary .txt'
if ($Interactive) {
    [void][System.Console]::ReadLine()
}
