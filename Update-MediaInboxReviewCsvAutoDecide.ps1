#requires -Version 5.1
<#
.SYNOPSIS
  Auto-populates Decision/DecisionNote and can repath review rows.
.DESCRIPTION
  Rules:
  - source under \_Workspace\ => SKIP (legacy noise)
  - rows with tmdb_movie/tmdb_tv note and non-review destination => APPLY
  - rows with episode_code_in_filename and non-review destination => APPLY
  - review rows: source-pattern series detection + episode parse => APPLY to cartoons (эпизод: S01E02, S01.E02, _S01E02_, последний SxxEyy в имени, 7xx «сезон+эпизод», Eps21-22, «… 3 (12)», ведущий номер)
  - optional torrent hints: fuzzy token match from .torrent names => APPLY for review rows
  - если в пути источника и в имени .torrent есть один и тот же rutracker-ID (rutracker-1234567) — жёсткое сопоставление без fuzzy
  - метаданные .torrent (bencode): слова из info.name и имён видеофайлов в раздаче; уникальное совпадение имени листа .mkv/.mp4/... с одной раздачей
  - опционально qBittorrent Web API: полный путь файла на диске клиента -> та же раздача (по info_hash), без хардкода URL (параметры или MIT_QBIT_*)
  - если файлы перенесли с каталога загрузок qBittorrent на NAS: префиксы -QbittorrentCsvSourcePrefix и -QbittorrentDownloadRootPrefix подставляют путь «как у клиента» для поиска в индексе
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$OutCsvPath = '',
    [string]$TorrentDirectory = '',
    [string]$QbittorrentWebUiUrl = '',
    [string]$QbittorrentUsername = '',
    [string]$QbittorrentPassword = '',
    [switch]$QbittorrentSkipCertificateCheck,
    [string]$QbittorrentCsvSourcePrefix = '',
    [string]$QbittorrentDownloadRootPrefix = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'TorrentBencode.ps1')
. (Join-Path $PSScriptRoot 'Qbittorrent-WebApi.ps1')

if ([string]::IsNullOrWhiteSpace($QbittorrentWebUiUrl)) {
    $QbittorrentWebUiUrl = [Environment]::GetEnvironmentVariable('MIT_QBIT_WEBUI')
}
if ($null -eq $QbittorrentWebUiUrl) { $QbittorrentWebUiUrl = '' }
if ([string]::IsNullOrWhiteSpace($QbittorrentUsername)) {
    $QbittorrentUsername = [Environment]::GetEnvironmentVariable('MIT_QBIT_USER')
}
if ($null -eq $QbittorrentUsername) { $QbittorrentUsername = '' }
if ([string]::IsNullOrWhiteSpace($QbittorrentPassword)) {
    $QbittorrentPassword = [Environment]::GetEnvironmentVariable('MIT_QBIT_PASS')
}
if ($null -eq $QbittorrentPassword) { $QbittorrentPassword = '' }
if ([string]::IsNullOrWhiteSpace($QbittorrentCsvSourcePrefix)) {
    $QbittorrentCsvSourcePrefix = [Environment]::GetEnvironmentVariable('MIT_QBIT_CSV_PREFIX')
}
if ($null -eq $QbittorrentCsvSourcePrefix) { $QbittorrentCsvSourcePrefix = '' }
if ([string]::IsNullOrWhiteSpace($QbittorrentDownloadRootPrefix)) {
    $QbittorrentDownloadRootPrefix = [Environment]::GetEnvironmentVariable('MIT_QBIT_DOWNLOAD_ROOT')
}
if ($null -eq $QbittorrentDownloadRootPrefix) { $QbittorrentDownloadRootPrefix = '' }

$CsvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)
if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }

if ([string]::IsNullOrWhiteSpace($OutCsvPath)) {
    $dir = Split-Path -Parent $CsvPath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $OutCsvPath = Join-Path $dir ($name + '.auto.csv')
}

function Normalize-TokenString {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $x = $s.ToLowerInvariant()
    $x = [regex]::Replace($x, "[^\p{L}0-9]+", ' ')
    $x = [regex]::Replace($x, '\s+', ' ').Trim()
    return $x
}

function Get-WordSet {
    param([string]$s)
    $n = Normalize-TokenString $s
    if ([string]::IsNullOrWhiteSpace($n)) { return @() }
    return @($n.Split(' ') | Where-Object { $_.Length -ge 4 } | Select-Object -Unique)
}

function Get-EpisodeInfo {
    param([string]$FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    function New-EpisodeInfoResult {
        param(
            [int]$Episode,
            [string]$Title,
            [int]$Season = 0,
            [string]$Series = ''
        )
        $t = $Title.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { $t = "Episode $Episode" }
        return [pscustomobject]@{
            Episode = $Episode
            Title     = $t
            Season    = $Season
            Series    = $Series
        }
    }

    $mCode = $null

    $mCode = [regex]::Match($base, '(?i)\bS(?<s>\d{1,2})E(?<ep>\d{1,3})\b')
    if (-not $mCode.Success) {
        $mCode = [regex]::Match($base, '(?i)\b(?<s>\d{1,2})x(?<ep>\d{1,3})\b')
    }
    if (-not $mCode.Success) {
        $mCode = [regex]::Match($base, '(?i)(?<![A-Za-z0-9])S(?<s>\d{1,2})\.E(?<ep>\d{1,3})(?![0-9])')
    }
    if (-not $mCode.Success) {
        $mCode = [regex]::Match($base, '(?i)(?:^|[._-])S(?<s>\d{1,2})E(?<ep>\d{1,3})(?=[._-]|$)')
    }

    if ($mCode.Success) {
        $sNum = 0
        $epCode = 0
        try { $sNum = [int]$mCode.Groups['s'].Value } catch { $sNum = 0 }
        try { $epCode = [int]$mCode.Groups['ep'].Value } catch { $epCode = 0 }
        if ($epCode -gt 0) {
            $tail = ($base.Substring($mCode.Index + $mCode.Length)).Trim(' ', '.', '-', '_')
            return (New-EpisodeInfoResult -Episode $epCode -Title $tail -Season $sNum)
        }
    }

    $allCodes = [regex]::Matches($base, '(?i)S(?<s>\d{1,2})E(?<ep>\d{1,3})')
    if ($allCodes.Count -gt 0) {
        $mCode = $allCodes[$allCodes.Count - 1]
        $sNum = 0
        $epCode = 0
        try { $sNum = [int]$mCode.Groups['s'].Value } catch { $sNum = 0 }
        try { $epCode = [int]$mCode.Groups['ep'].Value } catch { $epCode = 0 }
        if ($epCode -gt 0) {
            $tail = ($base.Substring($mCode.Index + $mCode.Length)).Trim(' ', '.', '-', '_')
            return (New-EpisodeInfoResult -Episode $epCode -Title $tail -Season $sNum)
        }
    }

    $mEps = [regex]::Match($base, '(?i)Eps(?<ep>\d{1,3})-\d{1,3}')
    if ($mEps.Success) {
        $epCode = 0
        try { $epCode = [int]$mEps.Groups['ep'].Value } catch { $epCode = 0 }
        if ($epCode -gt 0) {
            $tail = ($base.Substring($mEps.Index + $mEps.Length)).Trim(' ', '.', '-', '_')
            return (New-EpisodeInfoResult -Episode $epCode -Title $tail -Season 0)
        }
    }

    $mCram = [regex]::Match($base, '(?i)^(?<show>.+?)\s+(?<s>[1-9])(?<ep>\d{2})\s+(?<ttl>.+)$')
    if ($mCram.Success) {
        $sNum = 0
        $epCode = 0
        try { $sNum = [int]$mCram.Groups['s'].Value } catch { $sNum = 0 }
        try { $epCode = [int]$mCram.Groups['ep'].Value } catch { $epCode = 0 }
        $showGuess = $mCram.Groups['show'].Value.Trim()
        $ttl = $mCram.Groups['ttl'].Value.Trim()
        if ($sNum -gt 0 -and $epCode -ge 0 -and $epCode -le 99 -and -not [string]::IsNullOrWhiteSpace($ttl)) {
            return (New-EpisodeInfoResult -Episode $epCode -Title $ttl -Season $sNum -Series $showGuess)
        }
    }

    $mParen = [regex]::Match($base, '(?i)^(?<show>.+?)\s+(?<s>\d{1,2})\s+\((?<ep>\d{1,3})\)\s*$')
    if ($mParen.Success) {
        $sNum = 0
        $epCode = 0
        try { $sNum = [int]$mParen.Groups['s'].Value } catch { $sNum = 0 }
        try { $epCode = [int]$mParen.Groups['ep'].Value } catch { $epCode = 0 }
        $showRaw = $mParen.Groups['show'].Value.Trim()
        $showRaw = [regex]::Replace($showRaw, '^\[[^\]]+\]\s*', '').Trim()
        if ($sNum -gt 0 -and $epCode -gt 0 -and -not [string]::IsNullOrWhiteSpace($showRaw)) {
            $epTitle = ('Episode {0}' -f $epCode)
            return (New-EpisodeInfoResult -Episode $epCode -Title $epTitle -Season $sNum -Series $showRaw)
        }
    }

    $m = [regex]::Match($base, '^(?<ep>\d{1,3})[\.\s\-_]+(?<title>.+)$')
    if (-not $m.Success) { return $null }
    $ep = 0
    try { $ep = [int]$m.Groups['ep'].Value } catch { $ep = 0 }
    if ($ep -le 0) { return $null }
    $ttl = $m.Groups['title'].Value.Trim()
    return (New-EpisodeInfoResult -Episode $ep -Title $ttl -Season 0)
}

function Get-SourceTrackerTopicIds {
    param([string]$PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) { return @() }
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($m in [regex]::Matches($PathText, '(?i)rutracker[_-](\d{5,8})\b')) {
        [void]$set.Add($m.Groups[1].Value)
    }
    return @($set)
}

function Get-TorrentHintByTrackerTopicId {
    param(
        [string]$SourcePath,
        [object[]]$TorrentHints
    )
    if ($null -eq $TorrentHints -or $TorrentHints.Count -eq 0) { return $null }
    foreach ($tid in Get-SourceTrackerTopicIds $SourcePath) {
        $hit = $TorrentHints | Where-Object { $_.TopicId -eq $tid } | Select-Object -First 1
        if ($null -ne $hit) { return $hit }
    }
    return $null
}

function Resolve-SeriesFromPath {
    param([string]$SourcePath)
    $s = $SourcePath
    $patterns = @(
        @{ Re = "(?i)Archer(?:\.|\\| )?Season[\.\s_]*(?<s>\d{1,2})"; Name = "Archer" },
        @{ Re = "(?i)Robot\.Chicken(?:\.|\\| )S(?<s>\d{1,2})"; Name = "Robot Chicken" },
        @{ Re = "(?i)Robot\.Chicken(?:\.|\\| )Season[\.\s_]*(?<s>\d{1,2})"; Name = "Robot Chicken" },
        @{ Re = "(?i)King of the Hill(?:.*?Season[\.\s_]*(?<s>\d{1,2}))"; Name = "King of the Hill" },
        @{ Re = "(?i)Bob''s\.Burgers(?:\.|\\| )S(?<s>\d{1,2})"; Name = "Bobs Burgers" },
        @{ Re = "(?i)Fugget\.About\.It(?:\.|\\| )Season[\.\s_]*(?<s>\d{1,2})"; Name = "Fugget About It" },
        @{ Re = "(?i)Disenchantment(?:.*?Season[\.\s_]*(?<s>\d{1,2}))"; Name = "Disenchantment" },
        @{ Re = "(?i)Adventure Time(?:\s+with\s+Finn\s+and\s+Jake)?(?:\.|\\| | - )+Season[\.\s_]*(?<s>\d{1,2})"; Name = "Adventure Time" },
        @{ Re = "(?i)Adventure Time(?:.*?Season[\.\s_]*(?<s>\d{1,2}))"; Name = "Adventure Time" }
    )
    foreach ($p in $patterns) {
        $m = [regex]::Match($s, $p.Re)
        if ($m.Success) {
            $season = 0
            try { $season = [int]$m.Groups['s'].Value } catch { $season = 0 }
            if ($season -gt 0) {
                return [pscustomobject]@{ Series = $p.Name; Season = $season; Rule = $p.Name }
            }
        }
    }
    return $null
}

function Resolve-SeriesFromTorrentName {
    param([string]$TorrentName)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($TorrentName)
    $name = [regex]::Replace($name, '\[[^\]]+\]', ' ')
    $name = [regex]::Replace($name, '\([^\)]*\)', ' ')
    $name = [regex]::Replace($name, '(?i)\b(rutracker|teamhd|nnmclub|1080p|2160p|web[- ]?dl|bluray|bdrip|remux|hdr|dv|x264|x265|torrent)\b', ' ')
    $name = [regex]::Replace($name, '\s+', ' ').Trim(' ', '-', '.', '_')

    $season = 0
    $m = [regex]::Match($name, '(?i)(season|sezon|сезон)\s*(?<s>\d{1,2})')
    if ($m.Success) {
        try { $season = [int]$m.Groups['s'].Value } catch { $season = 0 }
    }

    $title = $name
    if ($m.Success -and $m.Index -gt 2) {
        $title = $name.Substring(0, $m.Index).Trim(' ', '-', '.', '_')
    }
    if ([string]::IsNullOrWhiteSpace($title)) { return $null }
    return [pscustomobject]@{ Series = $title; Season = $season }
}

function Build-CartoonDest {
    param(
        [string]$CurrentDestFullPath,
        [string]$SeriesName,
        [int]$Season,
        [int]$Episode,
        [string]$EpisodeTitle,
        [string]$Ext
    )
    $idx = $CurrentDestFullPath.IndexOf('\Video\')
    if ($idx -lt 0) { return $null }
    $root = $CurrentDestFullPath.Substring(0, $idx + 7)
    $leaf = '{0} - S{1:D2}E{2:D2} - {3}.{4}' -f $SeriesName, $Season, $Episode, $EpisodeTitle, $Ext
    return (Join-Path (Join-Path (Join-Path (Join-Path $root 'cartoons') $SeriesName) ("Season {0}" -f $Season)) $leaf)
}

function Try-ApplyTorrentHintToReviewRow {
    param(
        $Hint,
        $Epi,
        $Series,
        [string]$Src,
        [string]$CurrentDest,
        [string]$Note,
        [string]$Rule
    )
    if ($null -eq $Hint) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$Hint.Series)) { return $null }
    $seasonFromHint = [int]$Hint.Season
    if ($seasonFromHint -le 0 -and $null -ne $Series) { $seasonFromHint = [int]$Series.Season }
    if ($seasonFromHint -le 0 -and $null -ne $Epi) {
        try {
            $fs = [int]$Epi.Season
            if ($fs -gt 0) { $seasonFromHint = $fs }
        } catch { }
    }
    if ($seasonFromHint -le 0) { $seasonFromHint = 1 }
    $ext = [System.IO.Path]::GetExtension($src).TrimStart('.')
    $newDst = Build-CartoonDest -CurrentDestFullPath $CurrentDest -SeriesName ([string]$Hint.Series) -Season $seasonFromHint -Episode $Epi.Episode -EpisodeTitle $Epi.Title -Ext $ext
    if ([string]::IsNullOrWhiteSpace($newDst)) { return $null }
    return [pscustomobject]@{
        Dst           = $newDst
        DestRoot      = 'cartoons'
        Decision      = 'APPLY'
        DecisionNote  = $Note
        Rule          = $Rule
    }
}

function Get-TorrentHintByUniqueVideoLeaf {
    param(
        [string]$SourcePath,
        [object[]]$TorrentHints,
        [hashtable]$LeafToHintIndexes
    )
    if ($null -eq $TorrentHints -or $TorrentHints.Count -eq 0) { return $null }
    if ($null -eq $LeafToHintIndexes -or $LeafToHintIndexes.Count -eq 0) { return $null }
    $leaf = [System.IO.Path]::GetFileName($SourcePath)
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }
    $ext = [System.IO.Path]::GetExtension($leaf).TrimStart('.')
    if (-not (Test-VideoExtension -Ext $ext)) { return $null }
    $k = $leaf.ToLowerInvariant()
    $set = $LeafToHintIndexes[$k]
    if ($null -eq $set -or $set.Count -ne 1) { return $null }
    $onlyIx = -1
    foreach ($x in $set) { $onlyIx = $x; break }
    if ($onlyIx -lt 0) { return $null }
    return $TorrentHints[$onlyIx]
}

function Get-QbitPathKeysForLookup {
    param(
        [string]$SourceFullPath,
        [string]$CsvRootPrefix,
        [string]$QbittorrentDownloadRoot
    )
    $keys = [System.Collections.Generic.List[string]]::new()
    $k0 = Normalize-MediaInboxPathKey $SourceFullPath
    if (-not [string]::IsNullOrWhiteSpace($k0)) {
        [void]$keys.Add($k0)
    }
    if ([string]::IsNullOrWhiteSpace($CsvRootPrefix) -or [string]::IsNullOrWhiteSpace($QbittorrentDownloadRoot)) {
        return $keys.ToArray()
    }
    $pfx = Normalize-MediaInboxPathKey $CsvRootPrefix
    if ([string]::IsNullOrWhiteSpace($pfx) -or [string]::IsNullOrWhiteSpace($k0)) {
        return $keys.ToArray()
    }
    if (-not $k0.StartsWith($pfx, [StringComparison]::Ordinal)) {
        return $keys.ToArray()
    }
    $tail = $k0.Substring($pfx.Length).TrimStart('\')
    $dl = $QbittorrentDownloadRoot.TrimEnd('\')
    $candidate = if ([string]::IsNullOrWhiteSpace($tail)) { $dl } else { $dl + '\' + $tail }
    $k1 = Normalize-MediaInboxPathKey $candidate
    if (-not [string]::IsNullOrWhiteSpace($k1) -and -not $keys.Contains($k1)) {
        [void]$keys.Add($k1)
    }
    return $keys.ToArray()
}

function Find-BestTorrentHint {
    param(
        [string]$SourcePath,
        [object[]]$TorrentHints
    )
    if ($null -eq $TorrentHints -or $TorrentHints.Count -eq 0) { return $null }
    $sourceWords = Get-WordSet $SourcePath
    if ($sourceWords.Count -eq 0) { return $null }

    $best = $null
    $bestScore = 0
    foreach ($t in $TorrentHints) {
        $inter = @($sourceWords | Where-Object { $t.Words -contains $_ })
        $score = $inter.Count
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $t
        }
    }
    if ($bestScore -lt 4) { return $null }
    return [pscustomobject]@{ Torrent = $best; Score = $bestScore }
}

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) { throw "CSV has no rows: $CsvPath" }

$hasDecision = $rows[0].PSObject.Properties.Name -contains 'Decision'
$hasDecisionNote = $rows[0].PSObject.Properties.Name -contains 'DecisionNote'

$torrentHints = @()
if (-not [string]::IsNullOrWhiteSpace($TorrentDirectory)) {
    $td = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TorrentDirectory)
    if (Test-Path -LiteralPath $td) {
        $torrentHints = @(
            Get-ChildItem -LiteralPath $td -Filter '*.torrent' -File -ErrorAction SilentlyContinue | ForEach-Object {
                $parsed = Resolve-SeriesFromTorrentName -TorrentName $_.Name
                $topicId = ''
                $tm = [regex]::Match($_.Name, '(?i)rutracker[_-](\d{5,8})\b')
                if ($tm.Success) { $topicId = $tm.Groups[1].Value }
                $infoSha1 = ''
                $videoLeaves = [string[]]@()
                $meta = $null
                try {
                    $meta = Get-TorrentHintMeta -LiteralPath $_.FullName
                } catch {
                    $meta = $null
                }
                if ($null -ne $meta) {
                    $infoSha1 = [string]$meta.InfoSha1Hex
                    $videoLeaves = @($meta.VideoLeaves)
                    $metaBlob = [string]$meta.MetaBlob
                }
                else {
                    $metaBlob = ''
                }
                $wordSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($w in (Get-WordSet $_.Name)) { [void]$wordSet.Add($w) }
                foreach ($w in (Get-WordSet $metaBlob)) { [void]$wordSet.Add($w) }
                foreach ($vl in $videoLeaves) {
                    foreach ($w in (Get-WordSet $vl)) { [void]$wordSet.Add($w) }
                }
                [pscustomobject]@{
                    Name        = $_.Name
                    Full        = $_.FullName
                    TopicId     = $topicId
                    InfoSha1Hex = $infoSha1
                    VideoLeaves = $videoLeaves
                    Words       = @($wordSet | Where-Object { $_.Length -ge 4 })
                    Series      = if ($null -ne $parsed) { $parsed.Series } else { '' }
                    Season      = if ($null -ne $parsed) { [int]$parsed.Season } else { 0 }
                }
            }
        )
    }
}

$leafToHintIndexes = @{}
for ($hix = 0; $hix -lt $torrentHints.Count; $hix++) {
    foreach ($vl in $torrentHints[$hix].VideoLeaves) {
        if ([string]::IsNullOrWhiteSpace($vl)) { continue }
        $lk = $vl.ToLowerInvariant()
        if (-not $leafToHintIndexes.ContainsKey($lk)) {
            $leafToHintIndexes[$lk] = [System.Collections.Generic.HashSet[int]]::new()
        }
        [void]$leafToHintIndexes[$lk].Add($hix)
    }
}

$sha1ToHintIndex = @{}
for ($hix = 0; $hix -lt $torrentHints.Count; $hix++) {
    $hx = [string]$torrentHints[$hix].InfoSha1Hex
    if ([string]::IsNullOrWhiteSpace($hx)) { continue }
    if (-not $sha1ToHintIndex.ContainsKey($hx)) {
        $sha1ToHintIndex[$hx] = $hix
    }
}

$qbitPathToHint = @{}
$qbitSession = $null
if (-not [string]::IsNullOrWhiteSpace($QbittorrentWebUiUrl)) {
    try {
        $qbitSession = Connect-MediaInboxQbitWebApi -WebUiBaseUrl $QbittorrentWebUiUrl -Username $QbittorrentUsername -Password $QbittorrentPassword -SkipCertificateCheck:$QbittorrentSkipCertificateCheck
        $qbitPathToHint = Build-MediaInboxQbitFullPathIndex -Connection $qbitSession -InfoSha1HexToHintIndex $sha1ToHintIndex
    }
    catch {
        Write-Warning ('qBittorrent Web API skipped: {0}' -f $_.Exception.Message)
        $qbitPathToHint = @{}
        $qbitSession = $null
    }
}

$apply = 0
$skip = 0
$review = 0
$autoRepath = 0

$outRows = foreach ($r in $rows) {
    $src = [string]$r.SourceFullPath
    $dst = [string]$r.DestFullPath
    $notes = [string]$r.Notes
    $destRoot = [string]$r.DestRootKey
    $decision = if ($hasDecision) { [string]$r.Decision } else { '' }
    $decisionNote = if ($hasDecisionNote) { [string]$r.DecisionNote } else { '' }
    $humanOverride = if ($r.PSObject.Properties.Name -contains 'HumanOverride') { [string]$r.HumanOverride } else { '' }
    $humanComment = if ($r.PSObject.Properties.Name -contains 'HumanComment') { [string]$r.HumanComment } else { '' }
    $humanDestOverride = if ($r.PSObject.Properties.Name -contains 'HumanDestOverride') { [string]$r.HumanDestOverride } else { '' }
    $rule = ''

    if ($src -match '\\_Workspace\\') {
        $decision = 'SKIP'
        $decisionNote = 'legacy_workspace_noise'
        $rule = 'workspace_skip'
    }
    elseif (($destRoot -ne 'review') -and ($notes -match 'tmdb_movie:|tmdb_tv:')) {
        $decision = 'APPLY'
        if ([string]::IsNullOrWhiteSpace($decisionNote)) { $decisionNote = 'tmdb_resolved' }
        $rule = 'tmdb_apply'
    }
    elseif (($destRoot -ne 'review') -and ([string]$r.ContentKindReason -match 'episode_code_in_filename')) {
        $decision = 'APPLY'
        if ([string]::IsNullOrWhiteSpace($decisionNote)) { $decisionNote = 'episode_code_detected' }
        $rule = 'episode_code_apply'
    }
    elseif ($destRoot -eq 'review') {
        $series = Resolve-SeriesFromPath -SourcePath $src
        $epi = Get-EpisodeInfo -FileName ([System.IO.Path]::GetFileName($src))

        $seriesNameForDest = ''
        $seasonForDest = 0
        if ($null -ne $series) {
            $seriesNameForDest = [string]$series.Series
            $seasonForDest = [int]$series.Season
        }
        if ($null -ne $epi) {
            if ($epi.Season -gt 0) { $seasonForDest = [int]$epi.Season }
            if (-not [string]::IsNullOrWhiteSpace($epi.Series)) {
                if ([string]::IsNullOrWhiteSpace($seriesNameForDest)) {
                    $seriesNameForDest = [string]$epi.Series
                }
            }
        }
        if ($seasonForDest -gt 0 -and $null -ne $epi -and -not [string]::IsNullOrWhiteSpace($seriesNameForDest)) {
            $ext = [System.IO.Path]::GetExtension($src).TrimStart('.')
            $patNote = if ($null -ne $series) { "auto_from_source_pattern:$($series.Rule)" } else { 'auto_from_filename_episode' }
            $newDst = Build-CartoonDest -CurrentDestFullPath $dst -SeriesName $seriesNameForDest -Season $seasonForDest -Episode $epi.Episode -EpisodeTitle $epi.Title -Ext $ext
            if (-not [string]::IsNullOrWhiteSpace($newDst)) {
                $dst = $newDst
                $destRoot = 'cartoons'
                $decision = 'APPLY'
                $decisionNote = $patNote
                $rule = 'review_repath_apply'
                $autoRepath++
            }
        }

        if (($decision -ne 'APPLY') -and $null -ne $epi -and $torrentHints.Count -gt 0) {
            $topicHit = Get-TorrentHintByTrackerTopicId -SourcePath $src -TorrentHints $torrentHints
            $appliedTorrent = $null
            if ($null -ne $topicHit) {
                $appliedTorrent = Try-ApplyTorrentHintToReviewRow -Hint $topicHit -Epi $epi -Series $series -Src $src -CurrentDest $dst -Note "auto_from_rutracker_topic:$($topicHit.TopicId)" -Rule 'tracker_topic_repath_apply'
            }
            if ($null -eq $appliedTorrent -and $qbitPathToHint.Count -gt 0) {
                $qIx = $null
                foreach ($pathKey in (Get-QbitPathKeysForLookup -SourceFullPath $src -CsvRootPrefix $QbittorrentCsvSourcePrefix -QbittorrentDownloadRoot $QbittorrentDownloadRootPrefix)) {
                    if (-not [string]::IsNullOrWhiteSpace($pathKey) -and $qbitPathToHint.ContainsKey($pathKey)) {
                        $qIx = $qbitPathToHint[$pathKey]
                        break
                    }
                }
                if ($null -ne $qIx) {
                    $qHint = $torrentHints[$qIx]
                    $qNote = if (-not [string]::IsNullOrWhiteSpace([string]$qHint.TopicId)) {
                        "auto_from_qbit_path_topic:$($qHint.TopicId)"
                    } else {
                        'auto_from_qbit_path'
                    }
                    $appliedTorrent = Try-ApplyTorrentHintToReviewRow -Hint $qHint -Epi $epi -Series $series -Src $src -CurrentDest $dst -Note $qNote -Rule 'qbit_path_repath_apply'
                }
            }
            if ($null -eq $appliedTorrent) {
                $leafHit = Get-TorrentHintByUniqueVideoLeaf -SourcePath $src -TorrentHints $torrentHints -LeafToHintIndexes $leafToHintIndexes
                if ($null -ne $leafHit) {
                    $leafNote = if (-not [string]::IsNullOrWhiteSpace([string]$leafHit.TopicId)) {
                        "auto_from_rutracker_leaf:$($leafHit.TopicId)"
                    } else {
                        'auto_from_torrent_leaf_unique'
                    }
                    $appliedTorrent = Try-ApplyTorrentHintToReviewRow -Hint $leafHit -Epi $epi -Series $series -Src $src -CurrentDest $dst -Note $leafNote -Rule 'torrent_leaf_unique_repath_apply'
                }
            }
            if ($null -eq $appliedTorrent) {
                $hint = Find-BestTorrentHint -SourcePath $src -TorrentHints $torrentHints
                if ($null -ne $hint) {
                    $appliedTorrent = Try-ApplyTorrentHintToReviewRow -Hint $hint.Torrent -Epi $epi -Series $series -Src $src -CurrentDest $dst -Note "auto_from_torrent_score:$($hint.Score)" -Rule 'torrent_repath_apply'
                }
            }
            if ($null -ne $appliedTorrent) {
                $dst = $appliedTorrent.Dst
                $destRoot = $appliedTorrent.DestRoot
                $decision = $appliedTorrent.Decision
                $decisionNote = $appliedTorrent.DecisionNote
                $rule = $appliedTorrent.Rule
                $autoRepath++
            }
        }

        if ([string]::IsNullOrWhiteSpace($decision)) {
            $decision = 'REVIEW'
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($decision)) {
        $decision = 'REVIEW'
    }

    switch ($decision.ToUpperInvariant()) {
        'APPLY' { $apply++ }
        'SKIP' { $skip++ }
        default { $review++ }
    }

    [pscustomobject]@{
        HumanOverride         = $humanOverride
        HumanComment          = $humanComment
        HumanDestOverride     = $humanDestOverride
        Decision              = $decision
        DecisionNote          = $decisionNote
        AutoRule              = $rule
        SourceFullPath        = $src
        DestFullPath          = $dst
        Kind                  = [string]$r.Kind
        ContentKindGuess      = [string]$r.ContentKindGuess
        ContentKindConfidence = [string]$r.ContentKindConfidence
        ContentKindReason     = [string]$r.ContentKindReason
        DestRootKey           = $destRoot
        Confidence            = [string]$r.Confidence
        Notes                 = $notes
        DryRun                = [string]$r.DryRun
    }
}

$outRows | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Auto-decided CSV: $OutCsvPath"
Write-Host "APPLY: $apply  SKIP: $skip  REVIEW: $review  AutoRepath: $autoRepath"
$topicTagged = @($torrentHints | Where-Object { -not [string]::IsNullOrWhiteSpace($_.TopicId) }).Count
$leafIdx = $leafToHintIndexes.Count
$qbitN = $qbitPathToHint.Count
Write-Host "TorrentHints: $($torrentHints.Count)  (rutracker TopicId: $topicTagged)  videoLeafKeys: $leafIdx  qBitPathKeys: $qbitN"
