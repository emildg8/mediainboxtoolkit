#requires -Version 5.1
<#
.SYNOPSIS
  Пример: DryRun + Start-Transcript + краткий POST-RUN SUMMARY по последнему CSV в LOGS/.
#>
param(
    [string]$InboxPath = '\\Emilian_TNAS\emildg8\Video\Sort',
    [string]$PolicyPath = ''
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $PSScriptRoot 'sort-inbox.library-layout-emilian.example.json'
}
$logDir = Join-Path $PSScriptRoot 'LOGS'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $logDir ("transcript-dryrun-{0}.log" -f $stamp)
Start-Transcript -Path $log -Force
try {
    & (Join-Path $PSScriptRoot 'MediaInboxToolkit.ps1') `
        -PolicyPath $PolicyPath `
        -InboxPath $InboxPath `
        -DryRun -UseTmdb -SkipAutoVersion -SkipAutoSync
}
finally {
    try { Stop-Transcript } catch { }
}
$csv = Get-ChildItem -LiteralPath $logDir -Filter 'sort-inbox-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($csv) {
    $rows = Import-Csv -LiteralPath $csv.FullName
    $n = $rows.Count
    $reviewDest = @($rows | Where-Object { $_.DestFullPath -like '*\_SortReview\*' -or $_.DestFullPath -like '*_SortReview\*' }).Count
    $orphanMap = @($rows | Where-Object { $_.Notes -like '*sort_source:folder_season_episode_orphan_map*' }).Count
    $tvSpec = @($rows | Where-Object { $_.Notes -like '*sort_source:tv_special_filename*' }).Count
    Add-Content -LiteralPath $log -Encoding UTF8 -Value @(
        '',
        '--- POST-RUN SUMMARY ---',
        "CSV: $($csv.FullName)",
        "Rows: $n",
        "Dest under _SortReview: $reviewDest",
        "Notes sort_source:tv_special_filename: $tvSpec",
        "Notes sort_source:folder_season_episode_orphan_map: $orphanMap"
    )
}
Write-Host "Transcript: $log"
