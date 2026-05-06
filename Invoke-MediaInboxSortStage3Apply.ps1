#requires -Version 5.1
<#
.SYNOPSIS
  Этап 3 (перенос): MediaInboxToolkit с -Apply по той же политике и SortRoot, что и этап 1. SeriesToolkit — отдельно: .\Organize-SortVideoUnderSort.ps1 -DryRun / без -DryRun.
.PARAMETER Force
  Без паузы подтверждения (для автоматизации).
#>
[CmdletBinding()]
param(
    [string]$SortRoot = '',
    [string]$PolicyPath = '',
    [ValidateSet('Ascii', 'Cyrillic')]
    [string]$SkeletonProfile = 'Ascii',
    [switch]$Force
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

if (-not $Force) {
    Write-Host "Будет выполнен перенос (MediaInboxToolkit -Apply) из: $SortRoot"
    $r = Read-Host 'Введите YES для продолжения'
    if ($r -ne 'YES') {
        Write-Host 'Отменено.'
        return
    }
}

$mitRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    if ($SkeletonProfile -eq 'Cyrillic') {
        $PolicyPath = Join-Path $mitRoot 'sort-inbox.video-under-sort.cyrillic.example.json'
    } else {
        $PolicyPath = Join-Path $mitRoot 'sort-inbox.video-under-sort.example.json'
    }
}
if (-not (Test-Path -LiteralPath $SortRoot)) {
    throw "SortRoot not reachable: $SortRoot"
}

$mit = Join-Path $mitRoot 'MediaInboxToolkit.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mit `
    -PolicyPath $PolicyPath -InboxPath $SortRoot -UseTmdb -Apply -SkipAutoVersion -SkipAutoSync

Write-Host 'Done Apply. Then: Organize-SortVideoUnderSort.ps1 for SeriesToolkit (DryRun first).'
