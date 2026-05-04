#requires -Version 5.1
<#
.SYNOPSIS
  Точка входа MediaInboxToolkit — входная сортировка видео (NAS / локально), UTF-8, classification v2.
.NOTES
  Двухшаговый сценарий: MediaInboxToolkit.Orchestrate.ps1. GUI: Start-MediaInboxToolkitGui.ps1.
  Политика: classification.folderSeasonContext.orphanSeasonFolderSeriesMap для одиночной папки сезона.
  scope.excludeDirectoryNames — не сканировать вложенные каталоги (например _Workspace при разложении внутри Sort).
  План доработок классификации: docs/FIX-PLAN-SORT-CLASSIFICATION-202605.md; постеры/NFO: ../SeriesMetaExtrasToolkit/.
  classification: webTmdbResolve (DDG/Яндекс→TMDB id), featureMeter (ffprobe порог полного метра, по умолчанию 3600 с).
  shortFormEpisodeTitleGuess: короткие файлы без SxxEyy — поиск эпизода по названию в TMDB (Fetch: Find-TmdbTvEpisodeByTitleFuzzy).
#>
[CmdletBinding()]
param(
    [string]$PolicyPath = '',
    [string]$InboxPath = '',
    [string]$LogDirectory = '',
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$UseTmdb,
    [string]$TmdbApiKey = '',
    [switch]$SkipAutoVersion,
    [switch]$SkipAutoSync
)

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $PSScriptRoot 'sort-inbox.example.json'
}

if (-not $SkipAutoVersion) {
    $bump = Join-Path $PSScriptRoot 'Bump-Version.ps1'
    if (Test-Path -LiteralPath $bump) {
        try {
            & $bump -ProjectRoot $PSScriptRoot -ChangeNote "Автоинкремент при изменении MediaInboxToolkit.ps1."
        } catch { }
    }
}

$engine = Join-Path $PSScriptRoot 'MediaInboxToolkit.Engine.ps1'
if (-not (Test-Path -LiteralPath $engine)) {
    throw "Engine not found: $engine"
}

$runArgs = @{}
foreach ($k in $PSBoundParameters.Keys) {
    if ($k -in @('SkipAutoVersion', 'SkipAutoSync')) { continue }
    $runArgs[$k] = $PSBoundParameters[$k]
}
$runArgs['PolicyPath'] = $PolicyPath
if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $runArgs['LogDirectory'] = Join-Path $PSScriptRoot 'LOGS'
} else {
    $runArgs['LogDirectory'] = $LogDirectory
}

& $engine @runArgs

$syncScript = Join-Path $PSScriptRoot 'Sync-GitHub.ps1'
if ((-not $SkipAutoSync) -and (Test-Path -LiteralPath $syncScript)) {
    try { & $syncScript -ProjectRoot $PSScriptRoot } catch { }
}
