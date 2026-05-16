#requires -Version 5.1
<#
.SYNOPSIS
  Восстановление Sort после частичного rename/ST: вложенные сезоны, дубликаты SxxEyy, заглушки, TMDB-названия.
.EXAMPLE
  .\Repair-SortInboxLayout.ps1 -ConfigPath .\sort-rename.emilian-tnas.local.json -ReportPath .\..\..\LOGS\sort-repair-report.txt
  .\Repair-SortInboxLayout.ps1 -Apply
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SortRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [string]$ConfigPath = '',
    [string]$ReportPath = '',
    [switch]$Apply,
    [switch]$SkipTmdbTitles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$mitRoot = Split-Path -Parent $scriptRoot
$repoRoot = Split-Path -Parent $mitRoot
. (Join-Path $repoRoot 'Fetch-VideoMetadata.ps1')

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot 'sort-rename.emilian-tnas.local.json'
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot 'sort-rename.batch.example.json'
}
$cfgJson = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfigPath).Path, [System.Text.UTF8Encoding]::new($false))
$cfg = $cfgJson | ConvertFrom-Json
if ($SortRoot) { $cfg.sortRoot = $SortRoot }
$sortRootPath = [string]$cfg.sortRoot

$apiKey = $env:TMDB_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = [Environment]::GetEnvironmentVariable('TMDB_API_KEY', 'User')
}

$bonusesName = [string]$cfg.bonusesSubfolder
if ([string]::IsNullOrWhiteSpace($bonusesName)) { throw 'Config bonusesSubfolder required in UTF-8 JSON.' }
$seasonFmt = if ($cfg.seasonFolderFormat) { [string]$cfg.seasonFolderFormat } else { 'Season {0}' }

$log = [System.Collections.Generic.List[string]]::new()
$stats = @{ flattened = 0; deduped = 0; renamed = 0; tmdb = 0; bonuses = 0; removedDirs = 0 }

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

function Get-TvIdForShow([string]$ShowFolder) {
    foreach ($s in @($cfg.series)) {
        $ft = ConvertTo-SortSafeLeaf ([string]$s.folderTitle)
        if ($ShowFolder -eq $ft) { return [int]$s.tvId }
        if ($ShowFolder -eq ($ft -replace '\s*-\s*', ' ')) { return [int]$s.tvId }
    }
    return 0
}

function Test-PlaceholderTitle([string]$Title) {
    return ($Title -match '^(\u0421\u0435\u0440\u0438\u044F|\u042D\u043F\u0438\u0437\u043E\u0434|Episode) \d+$')
}

function Test-IsSeasonFolderName([string]$Name) {
    return ($Name -match '^\u0421\u0435\u0437\u043e\u043d\s+\d+$')
}

function Get-TmdbTitleMap([int]$TvId, [int]$Season) {
    if ($SkipTmdbTitles -or $TvId -le 0 -or [string]::IsNullOrWhiteSpace($apiKey)) { return @{} }
    if (-not (Get-Command Get-TmdbTvSeasonEpisodeTitleMap -ErrorAction SilentlyContinue)) { return @{} }
    return Get-TmdbTvSeasonEpisodeTitleMap -TvId $TvId -SeasonNumber $Season -ApiKey $apiKey -Language 'ru-RU'
}

function Get-ScoreForEpisodeFile {
    param(
        [string]$ShowFolder,
        [int]$TvId,
        [int]$Season,
        [int]$Episode,
        [string]$SeriesInName,
        [string]$Title,
        [hashtable]$TmdbMap
    )
    $score = 0
    if ($SeriesInName -eq $ShowFolder) { $score += 100 }
    elseif ($SeriesInName -match '^\u0421\u0435\u0437\u043e\u043d\s+\d+$') { $score -= 80 }
    elseif ($SeriesInName -ne $ShowFolder) { $score -= 40 }

    if (-not (Test-PlaceholderTitle $Title)) { $score += 60 }
    else { $score -= 50 }

    if ($TmdbMap -and $TmdbMap.ContainsKey([string]$Episode)) {
        $expected = ConvertTo-SortSafeLeaf ([string]$TmdbMap[[string]$Episode])
        $got = ConvertTo-SortSafeLeaf $Title
        if ($expected -eq $got) { $score += 200 }
        elseif ($expected -and $got -and ($expected.Contains($got) -or $got.Contains($expected))) { $score += 80 }
        elseif (Test-PlaceholderTitle $Title) { $score += 30 }
    }
    return $score
}

function Invoke-SafeMoveFile([string]$From, [string]$To) {
    if ($From -eq $To) { return }
    if (-not (Test-Path -LiteralPath $From)) { return }
    $parent = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $parent)) {
        if ($Apply) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }
    if (Test-Path -LiteralPath $To) { return }
    if ($Apply) {
        if ($PSCmdlet.ShouldProcess($From, "-> $To")) {
            Move-Item -LiteralPath $From -Destination $To
        }
    }
    else { Write-Log "PLAN $From -> $To" }
}

function Invoke-SafeRemoveFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($Apply) {
        if ($PSCmdlet.ShouldProcess($Path, 'Remove duplicate')) {
            Remove-Item -LiteralPath $Path -Force
        }
    }
    else { Write-Log "PLAN REMOVE $Path" }
}

$epRx = [regex]'^(?<series>.+?) - S(?<s>\d{2})E(?<e>\d{2}) - (?<title>.+?)\.(?<ext>mkv|mp4|avi)$'

Write-Log "Repair SortRoot=$sortRootPath Apply=$Apply"

# --- Phase 1: flatten Сезон N\Сезон N ---
Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $show = $_.Name
    Get-ChildItem -LiteralPath $_.FullName -Directory | Where-Object { Test-IsSeasonFolderName $_.Name } | ForEach-Object {
        $seasonDir = $_.FullName
        $nested = Join-Path $seasonDir $_.Name
        if (-not (Test-Path -LiteralPath $nested)) { return }
        Get-ChildItem -LiteralPath $nested -File | ForEach-Object {
            $m = $epRx.Match($_.Name)
            if ($m.Success) {
                $sn = [int]$m.Groups['s'].Value
                $en = [int]$m.Groups['e'].Value
                $title = $m.Groups['title'].Value
                $ext = $m.Groups['ext'].Value
                $newName = ('{0} - S{1:D2}E{2:D2} - {3}.{4}' -f $show, $sn, $en, $title, $ext)
            }
            else {
                $newName = $_.Name -replace ('^' + [regex]::Escape($_.Directory.Name) + ' - '), ($show + ' - ')
            }
            $dest = Join-Path $seasonDir $newName
            Invoke-SafeMoveFile $_.FullName $dest
            if ($Apply) { $script:stats.flattened++ }
        }
        if ($Apply -and (Test-Path -LiteralPath $nested)) {
            $left = @(Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0) {
                Remove-Item -LiteralPath $nested -Force -ErrorAction SilentlyContinue
                $script:stats.removedDirs++
            }
        }
    }
}

# --- Phase 2: loose video in show root -> Бонусы ---
Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $bonusDir = Join-Path $_.FullName $bonusesName
    Get-ChildItem -LiteralPath $_.FullName -File -Include *.mkv,*.mp4,*.avi -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = Join-Path $bonusDir $_.Name
        Invoke-SafeMoveFile $_.FullName $dest
        if ($Apply) { $script:stats.bonuses++ }
    }
}

# --- Phase 3: dedupe by SxxEyy (keep best) ---
Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $show = $_.Name
    $tvId = Get-TvIdForShow $show
    $groups = @{}
    Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.mkv,*.mp4,*.avi | Where-Object {
        $_.FullName -notmatch [regex]::Escape("\$bonusesName\")
    } | ForEach-Object {
        $m = $epRx.Match($_.Name)
        if (-not $m.Success) { return }
        $sn = [int]$m.Groups['s'].Value
        $en = [int]$m.Groups['e'].Value
        $key = '{0}|{1}|{2}' -f $show, $sn, $en
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [System.Collections.Generic.List[object]]::new() }
        [void]$groups[$key].Add([pscustomobject]@{
            File     = $_
            Series   = $m.Groups['series'].Value
            Title    = $m.Groups['title'].Value
            Season   = $sn
            Episode  = $en
            Ext      = $m.Groups['ext'].Value
        })
    }
    foreach ($key in $groups.Keys) {
        $list = $groups[$key]
        if ($list.Count -le 1) { continue }
        $sn = $list[0].Season
        $tmdbMap = Get-TmdbTitleMap $tvId $sn
        $scored = $list | ForEach-Object {
            $sc = Get-ScoreForEpisodeFile -ShowFolder $show -TvId $tvId -Season $_.Season -Episode $_.Episode `
                -SeriesInName $_.Series -Title $_.Title -TmdbMap $tmdbMap
            [pscustomobject]@{ Item = $_; Score = $sc }
        } | Sort-Object Score -Descending
        $winner = $scored[0].Item
        $showRoot = (Get-Item -LiteralPath (Join-Path $sortRootPath $show)).FullName
        $seasonDir = Join-Path $showRoot ($seasonFmt -f $winner.Season)
        if (-not (Test-Path -LiteralPath $seasonDir) -and $Apply) {
            New-Item -ItemType Directory -Path $seasonDir -Force | Out-Null
        }
        $tmdbMapW = Get-TmdbTitleMap $tvId $winner.Season
        $titleUse = $winner.Title
        if ($tmdbMapW.ContainsKey([string]$winner.Episode)) {
            $titleUse = ConvertTo-SortSafeLeaf ([string]$tmdbMapW[[string]$winner.Episode])
        }
        elseif (Test-PlaceholderTitle $titleUse) { $titleUse = $winner.Title }
        $targetName = ('{0} - S{1:D2}E{2:D2} - {3}.{4}' -f $show, $winner.Season, $winner.Episode, $titleUse, $winner.Ext)
        $targetPath = Join-Path $seasonDir $targetName
        foreach ($entry in $scored) {
            if ($entry.Item.File.FullName -eq $winner.File.FullName) {
                if ($entry.Item.File.FullName -ne $targetPath) {
                    Invoke-SafeMoveFile $entry.Item.File.FullName $targetPath
                }
                continue
            }
            Write-Log "DEDUP remove score=$($entry.Score): $($entry.Item.File.FullName) (kept score=$($scored[0].Score))"
            Invoke-SafeRemoveFile $entry.Item.File.FullName
            if ($Apply) { $script:stats.deduped++ }
        }
    }
}

# --- Phase 4: TMDB titles for placeholders + wrong prefix ---
Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $show = $_.Name
    $tvId = Get-TvIdForShow $show
    if ($tvId -le 0) { return }
    $seasonMaps = @{}
    Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.mkv,*.mp4 | Where-Object {
        $_.FullName -notmatch [regex]::Escape("\$bonusesName\")
    } | ForEach-Object {
        $m = $epRx.Match($_.Name)
        if (-not $m.Success) { return }
        $sn = [int]$m.Groups['s'].Value
        $en = [int]$m.Groups['e'].Value
        $series = $m.Groups['series'].Value
        $title = $m.Groups['title'].Value
        $ext = $m.Groups['ext'].Value
        $need = ($series -ne $show) -or (Test-PlaceholderTitle $title)
        if (-not $need) { return }
        if (-not $seasonMaps.ContainsKey($sn)) {
            $seasonMaps[$sn] = Get-TmdbTitleMap $tvId $sn
        }
        $map = $seasonMaps[$sn]
        if (-not $map.ContainsKey([string]$en)) { return }
        $ru = ConvertTo-SortSafeLeaf ([string]$map[[string]$en])
        if ([string]::IsNullOrWhiteSpace($ru)) { return }
        $newName = ('{0} - S{1:D2}E{2:D2} - {3}.{4}' -f $show, $sn, $en, $ru, $ext)
        $showRoot = (Get-Item -LiteralPath (Join-Path $sortRootPath $show)).FullName
        $seasonDir = Join-Path $showRoot ($seasonFmt -f $sn)
        if (-not (Test-Path -LiteralPath $seasonDir) -and $Apply) {
            New-Item -ItemType Directory -Path $seasonDir -Force | Out-Null
        }
        $dest = Join-Path $seasonDir $newName
        if ($_.FullName -ne $dest) {
            Invoke-SafeMoveFile $_.FullName $dest
            if ($Apply) { $script:stats.tmdb++ }
        }
    }
}

# --- Phase 5: remove empty nested season dirs ---
Get-ChildItem -LiteralPath $sortRootPath -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    Get-ChildItem -LiteralPath $_.FullName -Directory -Recurse | Where-Object { Test-IsSeasonFolderName $_.Name } | Sort-Object FullName -Descending | ForEach-Object {
        $parent = Split-Path -Parent $_.FullName
        if (Test-IsSeasonFolderName (Split-Path -Leaf $parent)) {
            $left = @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0 -and $Apply) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                $script:stats.removedDirs++
            }
        }
    }
}

Write-Log ("Stats: flattened={0} deduped={1} tmdb={2} bonuses={3} removedDirs={4}" -f $stats.flattened, $stats.deduped, $stats.tmdb, $stats.bonuses, $stats.removedDirs)

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $mitRoot ('LOGS\sort-repair-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$logDir = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
[System.IO.File]::WriteAllLines($ReportPath, $log, [Text.UTF8Encoding]::new($false))
Write-Log "Report: $ReportPath"
