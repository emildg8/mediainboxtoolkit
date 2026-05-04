#requires -Version 5.1
<#
.SYNOPSIS
  Публикует содержимое MediaInboxToolkit/ + Fetch в репозиторий https://github.com/emildg8/MediaInboxToolkit (ветка main).
.DESCRIPTION
  Запускать из корня монорепо Script_Rename_ALLVideo. Требуется git, remote `media-inbox` на этот URL.
#>
[CmdletBinding()]
param(
    [string]$MonorepoRoot = '',
    [string]$FetchSource = '',
    [string]$WorktreePath = '',
    [switch]$ForceWithLease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MonorepoRoot)) {
    $MonorepoRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($FetchSource)) {
    $FetchSource = Join-Path $MonorepoRoot 'Fetch-VideoMetadata.ps1'
}
if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
    $WorktreePath = Join-Path $MonorepoRoot '_mit_publish_tmp'
}

if (-not (Test-Path -LiteralPath $FetchSource)) { throw "Не найден Fetch: $FetchSource" }

Push-Location $MonorepoRoot
try {
    $prevEa = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    git branch -D mit-standalone-publish 2>&1 | Out-Null
    $ErrorActionPreference = $prevEa
    # git пишет прогресс в stderr — при $ErrorActionPreference Stop PowerShell 5.1 завершает скрипт
    $cmd = "cd /d `"$MonorepoRoot`" && git subtree split --prefix=MediaInboxToolkit -b mit-standalone-publish"
    cmd.exe /c $cmd
    if ($LASTEXITCODE -ne 0) { throw "git subtree split завершился с кодом $LASTEXITCODE" }
    if (Test-Path -LiteralPath $WorktreePath) {
        git worktree remove -f $WorktreePath 2>$null
        Remove-Item -LiteralPath $WorktreePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    git worktree add -f $WorktreePath mit-standalone-publish
    Copy-Item -LiteralPath $FetchSource -Destination (Join-Path $WorktreePath 'Fetch-VideoMetadata.ps1') -Force
    Push-Location $WorktreePath
    git add Fetch-VideoMetadata.ps1
    $st = git status --porcelain
    if ($st) {
        git commit -m "Sync Fetch-VideoMetadata.ps1 for standalone clone."
    }
    if ($ForceWithLease) {
        git push media-inbox HEAD:main --force-with-lease
    } else {
        git push media-inbox HEAD:main
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git push не удался (возможен non-fast-forward). Повторите с -ForceWithLease или подтяните remote."
    }

    $verJsonPath = Join-Path $WorktreePath 'version.json'
    if (Test-Path -LiteralPath $verJsonPath) {
        $verObj = Get-Content -LiteralPath $verJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sem = [string]$verObj.version
        if ($sem -match '^\d+\.\d+\.\d+$') {
            $tagName = "v$sem"
            $remoteTag = (git ls-remote --tags media-inbox "refs/tags/$tagName" 2>$null | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($remoteTag)) {
                Write-Host "Тег $tagName уже есть на media-inbox — push тега пропущен (релиз не дублируем)."
            }
            else {
                git tag -a $tagName -m "MediaInboxToolkit $sem" HEAD 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    git tag -f $tagName HEAD 2>&1 | Out-Null
                }
                git push media-inbox $tagName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "OK: отправлен тег $tagName — при наличии .github/workflows/release.yml на GitHub создаётся Release."
                }
                else {
                    Write-Warning "Не удалось отправить тег $tagName. Создайте вручную: git -C <worktree> push media-inbox $tagName"
                }
            }
        }
    }

    Pop-Location
    try {
        git worktree remove -f $WorktreePath 2>$null
    } catch { }
    if (Test-Path -LiteralPath $WorktreePath) {
        Remove-Item -LiteralPath $WorktreePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
}

Write-Host 'OK: remote media-inbox main updated.'
