#requires -Version 5.1
# media-library-layout JSON + UNC Video root (outside Sort\Video).

Set-StrictMode -Version Latest

function Get-DefaultMediaLibraryLayout {
    return [pscustomobject]@{
        SeriesEpisodeDestinationDir = 'cartoons'
        ScanRoots                   = @('cartoons')
        AnimeSeriesScanRoot         = ''
        OvaSubfolderName            = 'OVA'
        OvaFilenameRegex            = '(?i)\b(OVA|ONA|Special)\b'
        FuzzyEnabled                = $false
        FuzzyUniqueMinScore         = 6
        ExplicitRules               = @(
            [pscustomobject]@{
                Id          = 'RobotChicken'
                FileRegex   = '(?i)Robot\.Chicken'
                FolderRegex = '(?i)(Robot\s*Chicken|RoboChicken)'
                LibraryRoot = 'cartoons'
            }
        )
    }
}

function ConvertTo-MediaLibraryLayoutObject {
    param($JsonObj)
    $def = Get-DefaultMediaLibraryLayout
    if ($null -eq $JsonObj) { return $def }

    $rules = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $JsonObj.explicitRules) {
        foreach ($r in $JsonObj.explicitRules) {
            [void]$rules.Add([pscustomobject]@{
                    Id          = [string]$r.id
                    FileRegex   = [string]$r.fileRegex
                    FolderRegex = [string]$r.folderRegex
                    LibraryRoot = [string]$r.libraryRoot
                })
        }
    }
    if ($rules.Count -eq 0) {
        foreach ($x in $def.ExplicitRules) { [void]$rules.Add($x) }
    }

    $scan = @()
    if ($null -ne $JsonObj.scanRoots -and @($JsonObj.scanRoots).Count -gt 0) {
        $scan = @($JsonObj.scanRoots | ForEach-Object { [string]$_ })
    }
    else {
        $scan = @($def.ScanRoots)
    }

    return [pscustomobject]@{
        SeriesEpisodeDestinationDir = if ($JsonObj.seriesEpisodeDestinationDir) { [string]$JsonObj.seriesEpisodeDestinationDir } else { $def.SeriesEpisodeDestinationDir }
        ScanRoots                   = $scan
        AnimeSeriesScanRoot         = if ($JsonObj.animeSeriesScanRoot) { [string]$JsonObj.animeSeriesScanRoot } else { [string]$def.AnimeSeriesScanRoot }
        OvaSubfolderName            = if ($JsonObj.ovaSubfolderName) { [string]$JsonObj.ovaSubfolderName } else { $def.OvaSubfolderName }
        OvaFilenameRegex            = if ($JsonObj.ovaFilenameRegex) { [string]$JsonObj.ovaFilenameRegex } else { $def.OvaFilenameRegex }
        FuzzyEnabled                = if ($null -ne $JsonObj.fuzzyEnabled) { [bool]$JsonObj.fuzzyEnabled } else { $false }
        FuzzyUniqueMinScore         = if ($null -ne $JsonObj.fuzzyUniqueMinScore) { [int]$JsonObj.fuzzyUniqueMinScore } else { 6 }
        ExplicitRules               = $rules.ToArray()
    }
}

function Read-MediaLibraryLayout {
    param([string]$JsonPath)
    if ([string]::IsNullOrWhiteSpace($JsonPath) -or -not (Test-Path -LiteralPath $JsonPath)) {
        return Get-DefaultMediaLibraryLayout
    }
    $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $j = $raw | ConvertFrom-Json
    return (ConvertTo-MediaLibraryLayoutObject $j)
}

function Resolve-MediaLibraryVideoRoot {
    param(
        [string]$ExplicitRoot,
        [string]$PathHint
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitRoot)) {
        return $ExplicitRoot.TrimEnd('\')
    }
    $envR = [Environment]::GetEnvironmentVariable('MIT_VIDEO_LIBRARY_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($envR)) {
        return $envR.TrimEnd('\')
    }
    if (-not [string]::IsNullOrWhiteSpace($PathHint)) {
        $m = [regex]::Match($PathHint, '^(?<lr>.+\\Video)\\Sort\\Video\\', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            return $m.Groups['lr'].Value.TrimEnd('\')
        }
        $idx = $PathHint.IndexOf('\Video\', [StringComparison]::OrdinalIgnoreCase)
        if ($idx -ge 0) {
            return $PathHint.Substring(0, $idx + 7).TrimEnd('\')
        }
    }
    return $null
}

function Test-MediaLibraryOvaFilename {
    param(
        [string]$FileBaseName,
        [string]$OvaRegex
    )
    if ([string]::IsNullOrWhiteSpace($FileBaseName) -or [string]::IsNullOrWhiteSpace($OvaRegex)) { return $false }
    return [regex]::IsMatch($FileBaseName, $OvaRegex)
}

function Build-MediaLibrarySeriesIndex {
    param(
        [string]$LibraryVideoRoot,
        [string[]]$ScanRoots
    )
    $list = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($LibraryVideoRoot) -or $null -eq $ScanRoots) { return $list.ToArray() }
    foreach ($sr in $ScanRoots) {
        if ([string]::IsNullOrWhiteSpace($sr)) { continue }
        $p = Join-Path -Path $LibraryVideoRoot -ChildPath $sr
        if (-not (Test-Path -LiteralPath $p)) { continue }
        Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$list.Add([pscustomobject]@{
                    LibraryRoot   = $sr
                    SeriesFolder  = $_.Name
                })
        }
    }
    return $list.ToArray()
}
