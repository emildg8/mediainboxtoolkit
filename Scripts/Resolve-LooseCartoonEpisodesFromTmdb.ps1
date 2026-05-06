#requires -Version 5.1
<#
.SYNOPSIS
  Moves flat cartoon episode files into season folders and renames from TMDB (ru-RU titles).
.DESCRIPTION
  Dot-sources Fetch-VideoMetadata.ps1. TMDB key: Get-TmdbApiKeyFromEnvironment.
  UTF-8 JSON: Resolve-LooseCartoonEpisodesFromTmdb.config.json (cartoonsRoot, shows[].folder, shows[].tvId, seasonFolderFormat,
  matchLanguageFallbacks, guessReplacements, episodeGuessOverrides with optional displayTitle,
  torrentScanRoots — рекурсивный поиск .torrent; qbittorrent.webUiUrl + pathMap from/to для путей qBit vs NAS; MIT_QBIT_*).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'Resolve-LooseCartoonEpisodesFromTmdb.config.json'
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$CartoonsRoot = [string]$cfg.cartoonsRoot
$matchLang = if ($cfg.matchLanguage) { [string]$cfg.matchLanguage } else { 'en-US' }
$displayLang = if ($cfg.displayLanguage) { [string]$cfg.displayLanguage } else { 'ru-RU' }
$seasonFmt = if ($cfg.seasonFolderFormat) { [string]$cfg.seasonFolderFormat } else { 'Season {0}' }
$shows = @($cfg.shows)
$guessReplacements = @()
if ($cfg.PSObject.Properties.Name -contains 'guessReplacements' -and $null -ne $cfg.guessReplacements) {
    foreach ($gr in @($cfg.guessReplacements)) {
        if ($null -eq $gr) { continue }
        $pn = $gr.PSObject.Properties.Name
        $pat = if ($pn -contains 'pattern') { [string]$gr.pattern } else { '' }
        $rep = if ($pn -contains 'replacement') { [string]$gr.replacement } else { '' }
        if ([string]::IsNullOrWhiteSpace($pat)) { continue }
        try {
            $guessReplacements += [pscustomobject]@{ Pattern = [regex]::new($pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase); Replacement = $rep }
        }
        catch { }
    }
}

$fallbackLangs = @()
if ($cfg.PSObject.Properties.Name -contains 'matchLanguageFallbacks' -and $null -ne $cfg.matchLanguageFallbacks) {
    foreach ($fb in @($cfg.matchLanguageFallbacks)) {
        if ($null -eq $fb) { continue }
        $s = [string]$fb
        if (-not [string]::IsNullOrWhiteSpace($s)) { $fallbackLangs += $s.Trim() }
    }
}

$episodeGuessOverrides = @()
if ($cfg.PSObject.Properties.Name -contains 'episodeGuessOverrides' -and $null -ne $cfg.episodeGuessOverrides) {
    foreach ($ov in @($cfg.episodeGuessOverrides)) {
        if ($null -eq $ov) { continue }
        $pn = $ov.PSObject.Properties.Name
        $fld = if ($pn -contains 'folder') { [string]$ov.folder } else { '' }
        $pat = if ($pn -contains 'pattern') { [string]$ov.pattern } else { '' }
        if ([string]::IsNullOrWhiteSpace($fld) -or [string]::IsNullOrWhiteSpace($pat)) { continue }
        try {
            $rx = [regex]::new($pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        catch { continue }
        $snO = 0; $enO = 0
        try { $snO = [int]$ov.season } catch { }
        try { $enO = [int]$ov.episode } catch { }
        if ($snO -lt 0 -or $enO -le 0) { continue }
        $disp = if ($pn -contains 'displayTitle' -and -not [string]::IsNullOrWhiteSpace([string]$ov.displayTitle)) { [string]$ov.displayTitle.Trim() } else { '' }
        $episodeGuessOverrides += [pscustomobject]@{ Folder = $fld; Pattern = $rx; Season = $snO; Episode = $enO; DisplayTitle = $disp }
    }
}

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fetch = Join-Path $repoRoot 'Fetch-VideoMetadata.ps1'
if (-not (Test-Path -LiteralPath $fetch)) { throw "Not found: $fetch" }
. $fetch

if (-not (Get-Command Get-TmdbApiKeyFromEnvironment -ErrorAction SilentlyContinue)) { throw 'Get-TmdbApiKeyFromEnvironment missing' }
$key = Get-TmdbApiKeyFromEnvironment
if ([string]::IsNullOrWhiteSpace($key)) { throw 'TMDB API key not set.' }

$tscan = @()
if ($cfg.PSObject.Properties.Name -contains 'torrentScanRoots' -and $null -ne $cfg.torrentScanRoots) {
    foreach ($x in @($cfg.torrentScanRoots)) {
        if ($null -eq $x) { continue }
        $xp = [Environment]::ExpandEnvironmentVariables([string]$x).Trim()
        if (-not [string]::IsNullOrWhiteSpace($xp)) { $tscan += $xp }
    }
}
$mitRoot = Split-Path $PSScriptRoot -Parent
$mitTorrentEntries = [System.Collections.Generic.List[object]]::new()
$mitLeafToTorrentIdx = @{}
$mitQbitPathMap = $null
$mitQbitPathMaps = @()
$qbitSkipCert = $false
$qbitUrlCfg = ''
if ($cfg.PSObject.Properties.Name -contains 'qbittorrent' -and $null -ne $cfg.qbittorrent) {
    $qb = $cfg.qbittorrent
    $qbn = $qb.PSObject.Properties.Name
    if ($qbn -contains 'webUiUrl' -and -not [string]::IsNullOrWhiteSpace([string]$qb.webUiUrl)) {
        $qbitUrlCfg = [string]$qb.webUiUrl.Trim()
    }
    if ($qbn -contains 'skipCertificateCheck' -and $qb.skipCertificateCheck -eq $true) { $qbitSkipCert = $true }
    if ($qbn -contains 'pathMap' -and $null -ne $qb.pathMap) { $mitQbitPathMaps = @($qb.pathMap) }
}

if ($tscan.Count -gt 0) {
    . (Join-Path $mitRoot 'TorrentBencode.ps1')
    . (Join-Path $mitRoot 'Qbittorrent-WebApi.ps1')
    foreach ($tr in $tscan) {
        if (-not (Test-Path -LiteralPath $tr)) {
            Write-Warning "torrentScanRoots missing: $tr"
            continue
        }
        $torFiles = @(Get-ChildItem -LiteralPath $tr -Recurse -Filter *.torrent -File -ErrorAction SilentlyContinue)
        foreach ($tor in $torFiles) {
            $meta = Get-TorrentHintMeta -LiteralPath $tor.FullName
            if (-not $meta -or @($meta.VideoLeaves).Count -eq 0) { continue }
            $idx = $mitTorrentEntries.Count
            $bn = $tor.BaseName
            $blob = ($bn + ' ' + [string]$meta.MetaBlob)
            [void]$mitTorrentEntries.Add([pscustomobject]@{
                    TorrentPath = $tor.FullName
                    InfoSha1Hex = [string]$meta.InfoSha1Hex
                    Leaves      = @($meta.VideoLeaves)
                    Blob        = $blob
                })
            foreach ($leaf in @($meta.VideoLeaves)) {
                if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
                $k = $leaf.ToLowerInvariant()
                if (-not $mitLeafToTorrentIdx.ContainsKey($k)) {
                    $mitLeafToTorrentIdx[$k] = [System.Collections.Generic.List[int]]::new()
                }
                [void]$mitLeafToTorrentIdx[$k].Add($idx)
            }
        }
    }
    Write-Host "Torrent hint index: $($mitTorrentEntries.Count) torrents, $($mitLeafToTorrentIdx.Keys.Count) unique video leaves."
}

$qbitUrl = $qbitUrlCfg
if ([string]::IsNullOrWhiteSpace($qbitUrl)) { $qbitUrl = [Environment]::GetEnvironmentVariable('MIT_QBIT_WEBUI') }
if ($null -eq $qbitUrl) { $qbitUrl = '' }
$qbitUser = [Environment]::GetEnvironmentVariable('MIT_QBIT_USER')
if ($null -eq $qbitUser) { $qbitUser = '' }
$qbitPass = [Environment]::GetEnvironmentVariable('MIT_QBIT_PASS')
if ($null -eq $qbitPass) { $qbitPass = '' }

if ($mitTorrentEntries.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($qbitUrl)) {
    if (-not (Get-Command Connect-MediaInboxQbitWebApi -ErrorAction SilentlyContinue)) {
        . (Join-Path $mitRoot 'Qbittorrent-WebApi.ps1')
    }
    try {
        $qbitConn = Connect-MediaInboxQbitWebApi -WebUiBaseUrl $qbitUrl -Username $qbitUser -Password $qbitPass -SkipCertificateCheck:$qbitSkipCert
        $sha1ToHint = @{}
        for ($ti = 0; $ti -lt $mitTorrentEntries.Count; $ti++) {
            $hx = [string]$mitTorrentEntries[$ti].InfoSha1Hex
            if (-not $sha1ToHint.ContainsKey($hx)) { $sha1ToHint[$hx] = $ti }
        }
        $mitQbitPathMap = Build-MediaInboxQbitFullPathIndex -Connection $qbitConn -InfoSha1HexToHintIndex $sha1ToHint
        Write-Host "qBittorrent path index: $($mitQbitPathMap.Count) paths."
    }
    catch {
        Write-Warning "qBittorrent index failed: $($_.Exception.Message)"
        $mitQbitPathMap = $null
    }
}

function Mit-TryParseSeasonEpisodeFromText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $m = [regex]::Match($text, '(?i)\bS(\d{1,2})\s*E(\d{1,3})\b')
    if ($m.Success) {
        return @{ Season = [int]$m.Groups[1].Value; Episode = [int]$m.Groups[2].Value }
    }
    $m2 = [regex]::Match($text, '(?i)(?<![\d])(\d{1,2})x(\d{2,3})(?![\d])')
    if ($m2.Success) {
        $ep = [int]$m2.Groups[2].Value
        if ($ep -notin @(480, 540, 576, 720, 768, 900, 1080, 1440, 2160, 4320)) {
            return @{ Season = [int]$m2.Groups[1].Value; Episode = $ep }
        }
    }
    return $null
}

function Mit-TrySeasonEpisodeFromTorrentEntryIndexes {
    param(
        [System.Collections.Generic.List[int]]$CandidateIndexes,
        [System.Collections.Generic.List[object]]$TorrentEntries
    )
    if ($null -eq $CandidateIndexes -or $CandidateIndexes.Count -eq 0) { return $null }
    $distinct = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($ix in $CandidateIndexes) {
        if ($ix -lt 0 -or $ix -ge $TorrentEntries.Count) { continue }
        $e = $TorrentEntries[$ix]
        $found = Mit-TryParseSeasonEpisodeFromText $e.Blob
        if (-not $found) {
            foreach ($l in $e.Leaves) {
                $found = Mit-TryParseSeasonEpisodeFromText $l
                if ($found) { break }
            }
        }
        if ($found) { [void]$distinct.Add(('{0}:{1}' -f $found.Season, $found.Episode)) }
    }
    if ($distinct.Count -eq 1) {
        $parts = (@($distinct)[0]).Split(':')
        return @{ Season = [int]$parts[0]; Episode = [int]$parts[1] }
    }
    return $null
}

function Mit-TryTorrentHintSeasonEpisode {
    param(
        [System.IO.FileInfo]$VideoFile,
        [hashtable]$LeafToIdx,
        [System.Collections.Generic.List[object]]$Entries,
        $QbitPathMap,
        [object[]]$PathMaps
    )
    $leafKey = $VideoFile.Name.ToLowerInvariant()
    if ($LeafToIdx -and $LeafToIdx.ContainsKey($leafKey)) {
        $r = Mit-TrySeasonEpisodeFromTorrentEntryIndexes -CandidateIndexes $LeafToIdx[$leafKey] -TorrentEntries $Entries
        if ($r) { return $r }
    }
    if ($QbitPathMap -and (Get-Command Normalize-MediaInboxPathKey -ErrorAction SilentlyContinue)) {
        $keys = [System.Collections.Generic.List[string]]::new()
        [void]$keys.Add((Normalize-MediaInboxPathKey $VideoFile.FullName))
        foreach ($pm in $PathMaps) {
            if ($null -eq $pm) { continue }
            $pn = $pm.PSObject.Properties.Name
            $from = if ($pn -contains 'from') { [string]$pm.from } else { '' }
            $to = if ($pn -contains 'to') { [string]$pm.to } else { '' }
            if ([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($to)) { continue }
            $toNorm = $to.TrimEnd('\')
            if ($VideoFile.FullName.StartsWith($toNorm, [StringComparison]::OrdinalIgnoreCase)) {
                $fromNorm = $from.TrimEnd('\')
                $alt = $fromNorm + $VideoFile.FullName.Substring($toNorm.Length)
                [void]$keys.Add((Normalize-MediaInboxPathKey $alt))
            }
        }
        foreach ($qk in $keys) {
            if ([string]::IsNullOrWhiteSpace($qk)) { continue }
            if (-not $QbitPathMap.ContainsKey($qk)) { continue }
            $ix = [int]$QbitPathMap[$qk]
            if ($ix -lt 0 -or $ix -ge $Entries.Count) { continue }
            $e = $Entries[$ix]
            $pe = Mit-TryParseSeasonEpisodeFromText $e.Blob
            if (-not $pe) {
                foreach ($l in $e.Leaves) {
                    $pe = Mit-TryParseSeasonEpisodeFromText $l
                    if ($pe) { break }
                }
            }
            if ($pe) { return $pe }
        }
    }
    return $null
}

function ConvertTo-MitSafeFileLeaf([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 'Episode' }
    $t = $s.Trim()
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $t = $t.Replace([string]$c, '') }
    return ($t -replace '\s+', ' ').Trim()
}

function Build-MitLanguageChain([string]$Primary, [string[]]$Fallbacks) {
    $chain = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Primary)) { $chain.Add($Primary.Trim()) }
    foreach ($fb in $Fallbacks) {
        if ([string]::IsNullOrWhiteSpace($fb)) { continue }
        $t = $fb.Trim()
        if ($chain -notcontains $t) { $chain.Add($t) }
    }
    return @($chain)
}

function Test-MitTmdbEpisodeTitleIsGeneric([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t)) { return $true }
    $x = $t.Trim()
    if ($x -match '^(?i)Episode\s*\d') { return $true }
    if ($x -match '^(?i)\d+\s*$') { return $true }
    if ($x -match '^(?i)Эпизод\s*\d') { return $true }
    return $false
}

function Get-MitResolvedDisplayTitle([int]$TvId, [int]$SeasonNumber, [int]$EpisodeNumber, [string]$ApiKey, [string]$PreferredLang, [string]$FallbackDisplayLang) {
    $ek = [string]$EpisodeNumber
    $mapPref = Get-TmdbTvSeasonEpisodeTitleMap -TvId $TvId -SeasonNumber $SeasonNumber -ApiKey $ApiKey -Language $PreferredLang
    $t = ''
    if ($mapPref -and $mapPref.ContainsKey($ek)) { $t = [string]$mapPref[$ek] }
    if (-not (Test-MitTmdbEpisodeTitleIsGeneric $t)) { return $t.Trim() }
    if ([string]::IsNullOrWhiteSpace($FallbackDisplayLang) -or $FallbackDisplayLang -eq $PreferredLang) { return $t.Trim() }
    $mapFb = Get-TmdbTvSeasonEpisodeTitleMap -TvId $TvId -SeasonNumber $SeasonNumber -ApiKey $ApiKey -Language $FallbackDisplayLang
    if ($mapFb -and $mapFb.ContainsKey($ek)) {
        $t2 = [string]$mapFb[$ek]
        if (-not [string]::IsNullOrWhiteSpace($t2)) { return $t2.Trim() }
    }
    return $t.Trim()
}

foreach ($sh in $shows) {
    $folderName = [string]$sh.folder
    $tvId = [int]$sh.tvId
    $showMatchLang = $matchLang
    if ($sh.PSObject.Properties.Name -contains 'matchLanguage' -and -not [string]::IsNullOrWhiteSpace([string]$sh.matchLanguage)) {
        $showMatchLang = [string]$sh.matchLanguage.Trim()
    }
    $showDisplayLang = $displayLang
    if ($sh.PSObject.Properties.Name -contains 'displayLanguage' -and -not [string]::IsNullOrWhiteSpace([string]$sh.displayLanguage)) {
        $showDisplayLang = [string]$sh.displayLanguage.Trim()
    }
    $langChain = Build-MitLanguageChain $showMatchLang $fallbackLangs
    $root = Join-Path $CartoonsRoot $folderName
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Warning "Skip missing folder: $root"
        continue
    }
    $files = @(Get-ChildItem -LiteralPath $root -File)
    if ($files.Count -eq 0) { continue }
    Write-Host "=== $folderName ($($files.Count) files) tv=$tvId ==="
    foreach ($f in $files) {
        $guess = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ([string]::IsNullOrWhiteSpace($guess)) { continue }
        foreach ($gr in $guessReplacements) {
            if ($gr.Pattern.IsMatch($guess)) { $guess = $guess -replace $gr.Pattern, $gr.Replacement }
        }
        $hit = $null
        $overrideExplicitTitle = $false
        foreach ($ov in $episodeGuessOverrides) {
            if ($ov.Folder -ne $folderName) { continue }
            if ($ov.Pattern.IsMatch($guess)) {
                if (-not [string]::IsNullOrWhiteSpace($ov.DisplayTitle)) {
                    $hit = [pscustomobject]@{ Season = $ov.Season; Episode = $ov.Episode; MatchedTitle = $ov.DisplayTitle; OverrideExplicitTitle = $true }
                    $overrideExplicitTitle = $true
                }
                else {
                    $hit = [pscustomobject]@{ Season = $ov.Season; Episode = $ov.Episode; MatchedTitle = ''; OverrideExplicitTitle = $false }
                }
                break
            }
        }
        if (-not $hit) {
            foreach ($langTry in $langChain) {
                $hit = Find-TmdbTvEpisodeByTitleFuzzy -TvId $tvId -EpisodeTitleGuess $guess -ApiKey $key -Language $langTry -MaxSeasonsToScan 36
                if ($hit) { break }
            }
        }
        if (-not $hit) {
            $guessShort = ($guess -split '\s+' | Where-Object { $_.Length -ge 4 } | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($guessShort) -and $guessShort -ne $guess) {
                foreach ($langTry in $langChain) {
                    $hit = Find-TmdbTvEpisodeByTitleFuzzy -TvId $tvId -EpisodeTitleGuess $guessShort -ApiKey $key -Language $langTry -MaxSeasonsToScan 36
                    if ($hit) { break }
                }
            }
        }
        if (-not $hit -and $mitTorrentEntries.Count -gt 0) {
            $seT = Mit-TryTorrentHintSeasonEpisode -VideoFile $f -LeafToIdx $mitLeafToTorrentIdx -Entries $mitTorrentEntries -QbitPathMap $mitQbitPathMap -PathMaps $mitQbitPathMaps
            if ($seT) {
                $hit = [pscustomobject]@{ Season = $seT.Season; Episode = $seT.Episode; MatchedTitle = ''; OverrideExplicitTitle = $false }
                Write-Host "  (from torrent/qBittorrent: S$($seT.Season)E$($seT.Episode))"
            }
        }
        if (-not $hit) {
            Write-Warning "NO MATCH: $folderName :: $guess"
            continue
        }
        $sn = [int]$hit.Season
        $en = [int]$hit.Episode
        $seasonDir = Join-Path $root ($seasonFmt -f $sn)
        if ($PSCmdlet.ShouldProcess($f.FullName, "Move to $seasonDir")) {
            if (-not (Test-Path -LiteralPath $seasonDir)) {
                New-Item -ItemType Directory -Path $seasonDir -Force | Out-Null
            }
        }
        $titleRu = ConvertTo-MitSafeFileLeaf ([string]$hit.MatchedTitle)
        $useExplicit = ($hit.PSObject.Properties.Name -contains 'OverrideExplicitTitle') -and $hit.OverrideExplicitTitle
        if (-not $useExplicit -and (Get-Command Get-TmdbTvSeasonEpisodeTitleMap -ErrorAction SilentlyContinue)) {
            $tResolved = Get-MitResolvedDisplayTitle -TvId $tvId -SeasonNumber $sn -EpisodeNumber $en -ApiKey $key -PreferredLang $showDisplayLang -FallbackDisplayLang 'en-US'
            if (-not [string]::IsNullOrWhiteSpace($tResolved)) { $titleRu = ConvertTo-MitSafeFileLeaf $tResolved }
        }
        $newName = ('{0} - S{1:D2}E{2:D2} - {3}{4}' -f $folderName, $sn, $en, $titleRu, $f.Extension)
        $dest = Join-Path $seasonDir $newName
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "SKIP exists: $dest"
            continue
        }
        if ($PSCmdlet.ShouldProcess($f.FullName, "-> $dest")) {
            Move-Item -LiteralPath $f.FullName -Destination $dest
            Write-Host "OK S${sn}E${en}: $guess"
        }
    }
}
