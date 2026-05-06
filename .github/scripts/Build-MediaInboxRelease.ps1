#requires -Version 5.1
<#
.SYNOPSIS
  Собирает ZIP дистрибутива и Markdown-текст для GitHub Release (CI или локально).
.PARAMETER Version
  Семвер без префикса v, например 0.2.1; либо с префиксом — будет обрезан.
.PARAMETER OutDir
  Каталог для MediaInboxToolkit-<ver>.zip и release-body.md
.PARAMETER MonorepoChangelogUrl
  Ссылка на CHANGELOG в монорепо (ветка media-inbox-toolkit).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$MonorepoChangelogUrl = 'https://github.com/emildg8/SeriesToolkit/blob/master/MediaInboxToolkit/CHANGELOG.md',
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sem = ($Version.Trim() -replace '^v', '')
if ($sem -notmatch '^\d+\.\d+\.\d+$') { throw "Некорректная версия: $Version" }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$changelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $changelogPath)) { throw "Не найден CHANGELOG.md: $changelogPath" }

function Get-ChangelogBulletsForVersion {
    param([string]$Path, [string]$Sem)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $headerRe = [regex]::new("^\s*##\s+$([regex]::Escape($Sem))\s+-\s+")
    $in = $false
    $bullets = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in $lines) {
        if (-not $in) {
            if ($headerRe.IsMatch($ln)) { $in = $true }
            continue
        }
        if ($ln -match '^\s*##\s+') { break }
        if ($ln -match '^\s*-\s+') {
            $t = $ln.Trim()
            if ($t -match '(?i)^-\s*Snapshot:\s*OLD/') { continue }
            [void]$bullets.Add($t)
        }
    }
    return @($bullets)
}

$items = @(Get-ChangelogBulletsForVersion -Path $changelogPath -Sem $sem)
if ($items.Count -eq 0) {
    $items = @('- See CHANGELOG.md in the repo and commits for this tag.')
}

$zipName = "MediaInboxToolkit-$sem.zip"
$zipPath = Join-Path $OutDir $zipName
$bodyPath = Join-Path $OutDir 'release-body.md'
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$excludeDirs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($x in @('.git', '.github', 'OLD', 'LOGS')) { [void]$excludeDirs.Add($x) }

$stage = Join-Path $OutDir "_mit_zip_stage_$sem"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    Get-ChildItem -LiteralPath $RepoRoot -Force | ForEach-Object {
        if ($excludeDirs.Contains($_.Name)) { return }
        $dest = Join-Path $stage $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
    }
    $child = Join-Path $stage '*'
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        Compress-Archive -Path $child -DestinationPath $zipPath -CompressionLevel Optimal -Force
    }
    else {
        Compress-Archive -Path $child -DestinationPath $zipPath -Force
    }
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sizeKb = [int]([Math]::Ceiling((Get-Item -LiteralPath $zipPath).Length / 1024.0))

$bulletMd = ($items | ForEach-Object { $_.Trim() }) -join [Environment]::NewLine
$nl = [Environment]::NewLine
$tplPath = Join-Path $PSScriptRoot '..\templates\release-body.md.template'
if (-not (Test-Path -LiteralPath $tplPath)) { throw "Template not found: $tplPath" }
$utf8 = [System.Text.UTF8Encoding]::new($false)
$rawTpl = [System.IO.File]::ReadAllText($tplPath, $utf8)
$body = $rawTpl.
    Replace('{{SEM}}', $sem).
    Replace('{{ZIPNAME}}', $zipName).
    Replace('{{SIZEKB}}', [string]$sizeKb).
    Replace('{{SHA256}}', $hash).
    Replace('{{MONO_URL}}', $MonorepoChangelogUrl).
    Replace('{{BULLETS}}', $bulletMd)

[System.IO.File]::WriteAllText($bodyPath, $body.TrimStart([char]0xFEFF).TrimEnd() + $nl, [System.Text.UTF8Encoding]::new($false))

Write-Host "ZIP=$zipPath"
Write-Host "BODY=$bodyPath"
Write-Host "SHA256=$hash"
