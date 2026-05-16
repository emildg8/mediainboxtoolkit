#requires -Version 5.1
<#
.SYNOPSIS
  Принудительно выставляет RU-названия эпизодов по TMDB для всех SxxEyy в Sort (кроме Video).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SortRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [string]$ConfigPath = '',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'Fetch-VideoMetadata.ps1')

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'sort-rename.emilian-tnas.local.json'
}
$cfgJson = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfigPath).Path, [System.Text.UTF8Encoding]::new($false))
$cfg = $cfgJson | ConvertFrom-Json
$bonusesName = [string]$cfg.bonusesSubfolder
$seasonFmt = [string]$cfg.seasonFolderFormat

$apiKey = [Environment]::GetEnvironmentVariable('TMDB_API_KEY', 'User')
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'TMDB_API_KEY required' }

function ConvertTo-SortSafeLeaf([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return '_' }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch -or [char]::IsControl($ch)) { [void]$sb.Append(' ') }
        else { [void]$sb.Append($ch) }
    }
    $t = ($sb.ToString() -replace '\s{2,}', ' ').Trim() -replace '\s*:\s*', ' - '
    if ([string]::IsNullOrWhiteSpace($t)) { return '_' }
    return $t
}

$tvByShow = @{}
foreach ($s in @($cfg.series)) {
    $ft = ConvertTo-SortSafeLeaf ([string]$s.folderTitle)
    $tvByShow[$ft] = [int]$s.tvId
    $tvByShow[($ft -replace '\s*-\s*', ' ')] = [int]$s.tvId
}

$epRx = [regex]'^(?<series>.+?) - S(?<s>\d{2})E(?<e>\d{2}) - (?<title>.+?)\.(?<ext>mkv|mp4|avi)$'
$count = 0
Get-ChildItem -LiteralPath $SortRoot -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $show = $_.Name
    if (-not $tvByShow.ContainsKey($show)) { Write-Host "SKIP no tvId: $show"; return }
    $tvId = $tvByShow[$show]
    $maps = @{}
    Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.mkv,*.mp4 | Where-Object {
        $_.FullName -notmatch [regex]::Escape("\$bonusesName\")
    } | ForEach-Object {
        $m = $epRx.Match($_.Name)
        if (-not $m.Success) { return }
        $sn = [int]$m.Groups['s'].Value
        $en = [int]$m.Groups['e'].Value
        if (-not $maps.ContainsKey($sn)) {
            $maps[$sn] = Get-TmdbTvSeasonEpisodeTitleMap -TvId $tvId -SeasonNumber $sn -ApiKey $apiKey -Language 'ru-RU'
        }
        $map = $maps[$sn]
        if (-not $map.ContainsKey([string]$en)) { return }
        $ru = ConvertTo-SortSafeLeaf ([string]$map[[string]$en])
        $cur = $m.Groups['title'].Value
        if ($cur -eq $ru) { return }
        $ext = $m.Groups['ext'].Value
        $newName = ('{0} - S{1:D2}E{2:D2} - {3}.{4}' -f $show, $sn, $en, $ru, $ext)
        $showRoot = $_.Directory
        while ($showRoot -and (Split-Path -Leaf $showRoot) -ne $show) {
            if ((Split-Path -Leaf $showRoot) -match '^\u0421\u0435\u0437\u043e\u043d\s+\d+$') { break }
            $showRoot = Split-Path -Parent $showRoot
        }
        $seasonDir = if ($_.Directory.Name -match '^\u0421\u0435\u0437\u043e\u043d\s+\d+$') { $_.Directory.FullName } else {
            Join-Path (Get-Item -LiteralPath (Join-Path $SortRoot $show)).FullName ($seasonFmt -f $sn)
        }
        $dest = Join-Path $seasonDir $newName
        if ($_.FullName -eq $dest) { return }
        if ($Apply) {
            if ($PSCmdlet.ShouldProcess($_.Name, "-> $newName")) {
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
                Move-Item -LiteralPath $_.FullName -Destination $dest
                $script:count++
            }
        }
        else { Write-Host "PLAN $($_.Name) -> $newName" }
    }
}
Write-Host "Sync done: $count (Apply=$Apply)"
