#requires -Version 5.1
<#
.SYNOPSIS
  Исправляет вложенность «Сезон N\Сезон N\» после SeriesToolkit и возвращает имя сериала в файле.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SortRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Get-ChildItem -LiteralPath $SortRoot -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $show = $_.Name
    Get-ChildItem -LiteralPath $_.FullName -Directory | Where-Object { $_.Name -match '^Сезон\s+\d+$' } | ForEach-Object {
        $seasonDir = $_.FullName
        $nested = Join-Path $seasonDir $_.Name
        if (-not (Test-Path -LiteralPath $nested)) { return }
        Get-ChildItem -LiteralPath $nested -File | ForEach-Object {
            $newName = $_.Name -replace ('^' + [regex]::Escape($_.Directory.Name) + ' - '), ($show + ' - ')
            $dest = Join-Path $seasonDir $newName
            if ($Apply) {
                if ($PSCmdlet.ShouldProcess($_.FullName, "-> $dest")) {
                    Move-Item -LiteralPath $_.FullName -Destination $dest -Force
                }
            }
            else { Write-Host "PLAN $($_.FullName) -> $dest" }
        }
        if ($Apply -and (Test-Path -LiteralPath $nested)) {
            $left = Get-ChildItem -LiteralPath $nested -Force -ErrorAction SilentlyContinue
            if (-not $left) { Remove-Item -LiteralPath $nested -Force -ErrorAction SilentlyContinue }
        }
    }
}
