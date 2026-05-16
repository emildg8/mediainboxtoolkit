#requires -Version 5.1
<#
.SYNOPSIS
  Дозаполняет RU-названия эпизодов в уже переименованных SxxEyy (замена «Серия N» на TMDB).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SortRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'Fetch-VideoMetadata.ps1')

$apiKey = $env:TMDB_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = [Environment]::GetEnvironmentVariable('TMDB_API_KEY', 'User')
}
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'TMDB_API_KEY required' }

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

$rx = [regex]'^(?<series>.+?) - S(?<s>\d{2})E(?<e>\d{2}) - (?<title>.+?)\.(?<ext>mkv|mp4|avi)$'
$cfgPath = Join-Path $PSScriptRoot 'sort-rename.emilian-tnas.local.json'
$cfgJson = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $cfgPath).Path, [System.Text.UTF8Encoding]::new($false))
$cfg = $cfgJson | ConvertFrom-Json
$tvBySeries = @{}
foreach ($s in @($cfg.series)) {
    $ft = ConvertTo-SortSafeLeaf ([string]$s.folderTitle)
    $tvBySeries[$ft] = [int]$s.tvId
    $tvBySeries[($ft -replace '\s*-\s*', ' ')] = [int]$s.tvId
}

$count = 0
Get-ChildItem -LiteralPath $SortRoot -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $seriesFolder = $_.Name
    $tvId = 0
    if ($tvBySeries.ContainsKey($seriesFolder)) { $tvId = $tvBySeries[$seriesFolder] }
    Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.mkv,*.mp4 | ForEach-Object {
        $m = $rx.Match($_.Name)
        if (-not $m.Success) { return }
        if ($m.Groups['title'].Value -notmatch '^Серия \d+$') { return }
        if ($tvId -le 0) { return }
        $sn = [int]$m.Groups['s'].Value
        $en = [int]$m.Groups['e'].Value
        $map = Get-TmdbTvSeasonEpisodeTitleMap -TvId $tvId -SeasonNumber $sn -ApiKey $apiKey -Language 'ru-RU'
        $ru = $null
        if ($map.ContainsKey([string]$en)) { $ru = $map[[string]$en] }
        if ([string]::IsNullOrWhiteSpace($ru)) { return }
        $series = $m.Groups['series'].Value
        $ext = $m.Groups['ext'].Value
        $newName = ('{0} - S{1:D2}E{2:D2} - {3}.{4}' -f $series, $sn, $en, (ConvertTo-SortSafeLeaf $ru), $ext)
        $dest = Join-Path $_.DirectoryName $newName
        if ($_.FullName -eq $dest) { return }
        if ($Apply) {
            if ($PSCmdlet.ShouldProcess($_.FullName, "-> $newName")) {
                Rename-Item -LiteralPath $_.FullName -NewName $newName
                $script:count++
            }
        }
        else { Write-Host "PLAN $($_.Name) -> $newName" }
    }
}
Write-Host "Done. Updated: $count (Apply=$Apply)"
