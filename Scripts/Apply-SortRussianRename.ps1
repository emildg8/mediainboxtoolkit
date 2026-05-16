#requires -Version 5.1
<#
.SYNOPSIS
  Пакетное RU-переименование в инбоксе Sort: фильмы, сериалы/аниме (SxxEyy + TMDB), коллекции фильмов, бонусы в подпапку.
.EXAMPLE
  .\Apply-SortRussianRename.ps1 -ConfigPath .\sort-rename.batch.example.json -WhatIf
  .\Apply-SortRussianRename.ps1 -ConfigPath .\sort-rename.emilian-tnas.local.json -Apply
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath = '',
    [string]$SortRoot = '',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$mitRoot = Split-Path -Parent $scriptRoot
$repoRoot = Split-Path -Parent $mitRoot
$fetchPath = Join-Path $repoRoot 'Fetch-VideoMetadata.ps1'
if (-not (Test-Path -LiteralPath $fetchPath)) { throw "Fetch-VideoMetadata.ps1 not found: $fetchPath" }
. $fetchPath

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot 'sort-rename.batch.example.json'
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config not found: $ConfigPath" }

$cfgJson = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfigPath).Path, [System.Text.UTF8Encoding]::new($false))
$cfg = $cfgJson | ConvertFrom-Json
if (-not [string]::IsNullOrWhiteSpace($SortRoot)) { $cfg.sortRoot = $SortRoot }
$sortRootPath = [string]$cfg.sortRoot
if (-not (Test-Path -LiteralPath $sortRootPath)) { throw "Sort root not found: $sortRootPath" }

$apiKey = $env:TMDB_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    foreach ($scope in @('User', 'Machine')) {
        $apiKey = [Environment]::GetEnvironmentVariable('TMDB_API_KEY', $scope)
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) { break }
    }
}

$bonusesName = [string]$cfg.bonusesSubfolder
if ([string]::IsNullOrWhiteSpace($bonusesName)) { throw 'Config bonusesSubfolder is required (UTF-8 JSON).' }
$seasonFmt = [string]$cfg.seasonFolderFormat
if ([string]::IsNullOrWhiteSpace($seasonFmt)) { $seasonFmt = 'Season {0}' }
$epFallbackFmt = 'Episode {0}'
if ($cfg.PSObject.Properties.Name -contains 'episodeTitleFallback') {
    $epFallbackFmt = [string]$cfg.episodeTitleFallback
}
$epTpl = if ($cfg.episodeFilenameTemplate) { [string]$cfg.episodeFilenameTemplate } else { '{Series} - S{Season:D2}E{Episode:D2} - {Title}.{Ext}' }
$movTpl = if ($cfg.movieFilenameTemplate) { [string]$cfg.movieFilenameTemplate } else { '{Title}.{Ext}' }
$lang = 'ru-RU'
if ($cfg.displayNames -and $cfg.displayNames.tmdbLanguage) { $lang = [string]$cfg.displayNames.tmdbLanguage }
$bonusRx = if ($cfg.bonusesFilenamePattern) { [string]$cfg.bonusesFilenamePattern } else { '(?i)(\s-\s(ED|OP)\s)' }

$logDir = Join-Path $mitRoot 'LOGS'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logPath = Join-Path $logDir ("apply-sort-russian-rename-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$log = [System.Collections.Generic.List[string]]::new()

function Write-Log([string]$Msg) {
    $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $Msg
    $script:log.Add($line)
    Write-Host $line
}

function ConvertTo-SortSafeLeaf([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return '_' }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch -or [char]::IsControl($ch)) { [void]$sb.Append(' ') }
        else { [void]$sb.Append($ch) }
    }
    $t = ($sb.ToString() -replace '\s{2,}', ' ').Trim()
    $t = $t -replace '\s*:\s*', ' - '
    if ([string]::IsNullOrWhiteSpace($t)) { return '_' }
    return $t
}

function Get-MovieRuTitle([int]$MovieId, [string]$Fallback) {
    if ($MovieId -gt 0 -and -not [string]::IsNullOrWhiteSpace($apiKey) -and (Get-Command Get-TmdbMovieResolvedRuTitle -ErrorAction SilentlyContinue)) {
        $ru = Get-TmdbMovieResolvedRuTitle -MovieId $MovieId -ApiKey $apiKey
        if (-not [string]::IsNullOrWhiteSpace($ru)) { return (ConvertTo-SortSafeLeaf $ru) }
    }
    return (ConvertTo-SortSafeLeaf $Fallback)
}

function Get-EpisodeRuTitle([int]$TvId, [int]$Season, [int]$Episode) {
    if ($TvId -gt 0 -and -not [string]::IsNullOrWhiteSpace($apiKey) -and (Get-Command Get-TmdbTvSeasonEpisodeTitleMap -ErrorAction SilentlyContinue)) {
        $map = Get-TmdbTvSeasonEpisodeTitleMap -TvId $TvId -SeasonNumber $Season -ApiKey $apiKey -Language $lang
        if ($map) {
            foreach ($key in @($Episode, [string]$Episode)) {
                if ($map.ContainsKey($key)) {
                    $t = [string]$map[$key]
                    if (-not [string]::IsNullOrWhiteSpace($t)) { return (ConvertTo-SortSafeLeaf $t) }
                }
            }
        }
    }
    return ($epFallbackFmt -f $Episode)
}

function Invoke-SafeRename([string]$From, [string]$To) {
    if ($From -eq $To) { return }
    if (-not (Test-Path -LiteralPath $From)) {
        Write-Log "SKIP missing: $From"
        return
    }
    if (Test-Path -LiteralPath $To) {
        Write-Log "SKIP exists: $To"
        return
    }
    $parent = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $parent)) {
        if ($PSCmdlet.ShouldProcess($parent, 'Create directory')) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }
    if ($Apply) {
        if ($PSCmdlet.ShouldProcess($From, "-> $To")) {
            Move-Item -LiteralPath $From -Destination $To
            Write-Log "OK $From -> $To"
        }
    }
    else {
        Write-Log "PLAN $From -> $To"
    }
}

function Test-IsBonusFile([string]$FileName, [string]$ExtraPattern) {
    if ($FileName -match $bonusRx) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($ExtraPattern) -and $FileName -match $ExtraPattern) { return $true }
    return $false
}

function Format-EpisodeName([string]$Series, [int]$Season, [int]$Episode, [string]$Title, [string]$Ext) {
    $epTpl.Replace('{Series}', $Series).Replace('{Season:D2}', ('{0:D2}' -f $Season)).Replace('{Episode:D2}', ('{0:D2}' -f $Episode)).Replace('{Title}', $Title).Replace('{Ext}', $Ext.TrimStart('.'))
}

Write-Log "SortRoot=$sortRootPath Apply=$Apply Config=$ConfigPath"

# --- Movies in inbox root ---
foreach ($row in @($cfg.movies)) {
    if (($row.PSObject.Properties.Name -contains 'skip') -and [bool]$row.skip) { continue }
    $rx = [string]$row.match
    foreach ($f in @(Get-ChildItem -LiteralPath $sortRootPath -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension -notmatch '^\.(mkv|mp4|avi|m4v|mov|wmv|webm|mpeg|mpg)$') { continue }
        if ($f.Name -notmatch $rx) { continue }
        $title = ConvertTo-SortSafeLeaf ([string]$row.title)
        $newName = $movTpl.Replace('{Title}', $title).Replace('{Ext}', $f.Extension.TrimStart('.'))
        $dest = Join-Path $sortRootPath $newName
        Invoke-SafeRename $f.FullName $dest
    }
}

# --- Movie collections (e.g. KnK) ---
foreach ($coll in @($cfg.movieCollections)) {
    $folderRx = [string]$coll.folderMatch
    $dir = Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object { $_.Name -match $folderRx } | Select-Object -First 1
    if (-not $dir) { Write-Log "Collection folder not found: $folderRx"; continue }
    $seriesFolder = ConvertTo-SortSafeLeaf ([string]$coll.folderTitle)
    $targetRoot = Join-Path $sortRootPath $seriesFolder
    if ($dir.FullName -ne $targetRoot) {
        Invoke-SafeRename $dir.FullName $targetRoot
    }
    $collPath = $targetRoot
    if (-not (Test-Path -LiteralPath $collPath)) { $collPath = $dir.FullName }
    $bonusDir = Join-Path $collPath $bonusesName
    $bonusPat = if ($coll.bonusesPattern) { [string]$coll.bonusesPattern } else { '' }
    foreach ($f in @(Get-ChildItem -LiteralPath $collPath -File)) {
        $matched = $false
        foreach ($spec in @($coll.files)) {
            if ($f.Name -notmatch [string]$spec.match) { continue }
            $matched = $true
            $isBonus = $false
            if ($spec.PSObject.Properties.Name -contains 'bonus') { $isBonus = [bool]$spec.bonus }
            if ($isBonus -or (Test-IsBonusFile $f.Name $bonusPat)) {
                $leaf = ConvertTo-SortSafeLeaf $f.BaseName
                $dest = Join-Path $bonusDir ("{0}{1}" -f $leaf, $f.Extension)
                Invoke-SafeRename $f.FullName $dest
                break
            }
            $mid = [int]$spec.tmdbMovieId
            $ru = Get-MovieRuTitle $mid $f.BaseName
            $dest = Join-Path $collPath ("{0}{1}" -f $ru, $f.Extension)
            Invoke-SafeRename $f.FullName $dest
            break
        }
        if (-not $matched) {
            if (Test-IsBonusFile $f.Name $bonusPat) {
                $leaf = ConvertTo-SortSafeLeaf $f.BaseName
                $dest = Join-Path $bonusDir ("{0}{1}" -f $leaf, $f.Extension)
                Invoke-SafeRename $f.FullName $dest
            }
            else {
                Write-Log "UNMATCHED in collection: $($f.FullName)"
            }
        }
    }
}

# --- Series folders: сначала S1 (новая папка), затем merge S2 в ту же папку ---
$seriesSorted = @(
    $cfg.series | Sort-Object {
        $m = $false
        if ($_.PSObject.Properties.Name -contains 'mergeIntoExistingSeason') { $m = [bool]$_.mergeIntoExistingSeason }
        if ($m) { 1 } else { 0 }
    }, { -[string]$_.folderMatch.Length }
)
$processedDirs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($spec in $seriesSorted) {
    $folderRx = [string]$spec.folderMatch
    $dir = Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object {
        $_.Name -match $folderRx -and -not $processedDirs.Contains($_.FullName)
    } | Select-Object -First 1
    if (-not $dir) { continue }
    [void]$processedDirs.Add($dir.FullName)

    $tvId = [int]$spec.tvId
    $season = [int]$spec.season
    $seriesTitle = ConvertTo-SortSafeLeaf ([string]$spec.folderTitle)
    $epPat = [string]$spec.episodePattern
    $merge = $false
    if ($spec.PSObject.Properties.Name -contains 'mergeIntoExistingSeason') { $merge = [bool]$spec.mergeIntoExistingSeason }

    $seriesRoot = Join-Path $sortRootPath $seriesTitle
    if (-not (Test-Path -LiteralPath $seriesRoot)) {
        $existing = Get-ChildItem -LiteralPath $sortRootPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $seriesTitle } | Select-Object -First 1
        if ($existing) { $seriesRoot = $existing.FullName }
    }
    $seasonDir = Join-Path $seriesRoot ($seasonFmt -f $season)
    $bonusDir = Join-Path $seriesRoot $bonusesName
    $fileRoots = @()

    if ($merge) {
        if (-not (Test-Path -LiteralPath $seriesRoot)) {
            Write-Log "WARN merge but series root missing: $seriesTitle - processing as new root"
            Invoke-SafeRename $dir.FullName $seriesRoot
        }
        $fileRoots = @($dir.FullName)
    }
    else {
        if ($dir.FullName -ne $seriesRoot) { Invoke-SafeRename $dir.FullName $seriesRoot }
        $fileRoots = @($seriesRoot)
    }

    foreach ($root in $fileRoots) {
        foreach ($f in @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue)) {
            if (Test-IsBonusFile $f.Name '') {
                $leaf = ConvertTo-SortSafeLeaf $f.BaseName
                $dest = Join-Path $bonusDir ("{0}{1}" -f $leaf, $f.Extension)
                Invoke-SafeRename $f.FullName $dest
                continue
            }
            $m = [regex]::Match($f.Name, $epPat)
            if (-not $m.Success) {
                Write-Log "SKIP non-episode: $($f.FullName)"
                continue
            }
            $epNum = 0
            $sn = $season
            if ($m.Groups['s'].Success) { $sn = [int]$m.Groups['s'].Value }
            if ($m.Groups['e'].Success) { $epNum = [int]$m.Groups['e'].Value }
            $title = Get-EpisodeRuTitle $tvId $sn $epNum
            $newName = Format-EpisodeName $seriesTitle $sn $epNum $title $f.Extension
            $dest = Join-Path $seasonDir $newName
            Invoke-SafeRename $f.FullName $dest
        }
    }

    if ($merge -and (Test-Path -LiteralPath $dir.FullName) -and $dir.FullName -ne $seriesRoot) {
        if ($Apply) {
            $left = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Removed empty merge folder: $($dir.FullName)"
            }
        }
    }
}

[System.IO.File]::WriteAllLines($logPath, $log, [Text.UTF8Encoding]::new($false))
Write-Log "Log: $logPath"
