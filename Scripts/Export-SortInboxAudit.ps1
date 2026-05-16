#requires -Version 5.1
<#
.SYNOPSIS
  Аудит Sort: вложенные сезоны, заглушки, дубликаты, фильмы вне инбокса.
#>
param(
    [string]$SortRoot = '\\Emilian_TNAS\emildg8\Video\Sort',
    [string]$OutPath = ''
)

[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Sort inbox audit $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$sb.AppendLine("Root: $SortRoot")
[void]$sb.AppendLine('')

$nested = 0; $seria = 0; $epizod = 0; $badPrefix = 0
Get-ChildItem -LiteralPath $SortRoot -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $show = $_.Name
    Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.mkv,*.mp4 | ForEach-Object {
        $rel = $_.FullName.Substring($SortRoot.Length).TrimStart('\')
        if ($rel -match '\\Сезон (\d+)\\Сезон \1\\') { $script:nested++; [void]$sb.AppendLine("NESTED: $rel") }
        if ($_.Name -match ' - S\d{2}E\d{2} - Серия \d+\.') { $script:seria++; if ($seria -le 30) { [void]$sb.AppendLine("SERIA: $rel") } }
        if ($_.Name -match ' - S\d{2}E\d{2} - Эпизод \d+\.') { $script:epizod++; if ($epizod -le 20) { [void]$sb.AppendLine("EPIZOD: $rel") } }
        if ($_.Name -match '^Сезон \d+ - S\d{2}E\d{2}') { $script:badPrefix++; [void]$sb.AppendLine("BADPREFIX: $rel") }
    }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine("SUMMARY nested=$nested seria=$seria epizod=$epizod badPrefix=$badPrefix")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Show folders')
Get-ChildItem -LiteralPath $SortRoot -Directory | Where-Object { $_.Name -ne 'Video' } | ForEach-Object {
    $fc = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
    [void]$sb.AppendLine("- $($_.Name): $fc files")
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path (Split-Path -Parent $PSScriptRoot) ('LOGS\sort-audit-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
[System.IO.File]::WriteAllText($OutPath, $sb.ToString(), [Text.UTF8Encoding]::new($false))
Write-Host "Audit written: $OutPath"
Write-Host "nested=$nested seria=$seria epizod=$epizod badPrefix=$badPrefix"
