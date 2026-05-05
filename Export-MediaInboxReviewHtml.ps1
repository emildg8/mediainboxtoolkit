#requires -Version 5.1
<#
.SYNOPSIS
  Человекочитаемый HTML-отчёт по review CSV (цвета строк, блок «сначала проверь»).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [string]$OutHtmlPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CsvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)
if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }

if ([string]::IsNullOrWhiteSpace($OutHtmlPath)) {
    $dir = Split-Path -Parent $CsvPath
    $name = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $OutHtmlPath = Join-Path $dir ($name + '.html')
}

function Escape-HtmlCell {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) { throw "CSV has no rows: $CsvPath" }

$decisionCol = 'Decision'

$byDec = @{ APPLY = 0; SKIP = 0; REVIEW = 0; OTHER = 0 }
foreach ($r in $rows) {
    $d = ([string]$r.$decisionCol).Trim().ToUpperInvariant()
    if ($byDec.ContainsKey($d)) { $byDec[$d]++ } else { $byDec['OTHER']++ }
}

function Row-Class {
    param([string]$Decision)
    $u = $Decision.Trim().ToUpperInvariant()
    switch ($u) {
        'APPLY' { return 'row-apply' }
        'SKIP' { return 'row-skip' }
        'REVIEW' { return 'row-review' }
        default { return 'row-other' }
    }
}

function Build-TableRows {
    param([object[]]$RowSet)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in $RowSet) {
        $dec = [string]$r.$decisionCol
        $cls = Row-Class $dec
        [void]$sb.Append("<tr class=`"$cls`">")
        foreach ($col in $displayCols) {
            $val = if ($r.PSObject.Properties.Name -contains $col) { [string]$r.$col } else { '' }
            [void]$sb.Append('<td>').Append((Escape-HtmlCell $val)).Append('</td>')
        }
        [void]$sb.AppendLine('</tr>')
    }
    return $sb.ToString()
}

# Колонки в порядке «сначала важное для человека»
$displayCols = @(
    'HumanOverride', 'HumanComment', 'HumanDestOverride',
    'Decision', 'DecisionNote', 'AutoRule',
    'DestRootKey', 'Confidence', 'ContentKindGuess', 'ContentKindReason',
    'SourceFullPath', 'DestFullPath', 'Notes'
) | Where-Object {
    $c = $_
    $rows[0].PSObject.Properties.Name -contains $c
}

if ($displayCols.Count -eq 0) {
    $displayCols = @($rows[0].PSObject.Properties.Name)
}

$reviewRows = @($rows | Where-Object { ([string]$_.$decisionCol).Trim().ToUpperInvariant() -eq 'REVIEW' })
$applyRows = @($rows | Where-Object { ([string]$_.$decisionCol).Trim().ToUpperInvariant() -eq 'APPLY' })
$skipRows = @($rows | Where-Object { ([string]$_.$decisionCol).Trim().ToUpperInvariant() -eq 'SKIP' })

$thead = '<tr>' + (($displayCols | ForEach-Object { "<th>$(Escape-HtmlCell $_)</th>" }) -join '') + '</tr>'

$html = @"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>MediaInboxToolkit — разбор CSV</title>
<style>
  :root { font-family: "Segoe UI", system-ui, sans-serif; font-size: 13px; }
  body { margin: 16px 24px 48px; color: #1a1a1a; background: #fafafa; }
  h1 { font-size: 1.35rem; margin-bottom: 0.25rem; }
  .meta { color: #555; margin-bottom: 1rem; }
  .legend { display: flex; flex-wrap: wrap; gap: 12px; margin: 12px 0 20px; }
  .legend span { padding: 4px 10px; border-radius: 4px; font-size: 12px; }
  .lg-apply { background: #c8e6c9; }
  .lg-review { background: #fff9c4; }
  .lg-skip { background: #e0e0e0; }
  .hint { background: #e3f2fd; border-left: 4px solid #1976d2; padding: 12px 16px; margin: 16px 0; max-width: 900px; }
  .stats { margin: 8px 0 20px; }
  .stats li { margin: 4px 0; }
  h2 { font-size: 1.1rem; margin-top: 28px; border-bottom: 1px solid #ccc; padding-bottom: 6px; }
  .wrap { overflow-x: auto; border: 1px solid #ddd; border-radius: 6px; background: #fff; margin-bottom: 24px; }
  table { border-collapse: collapse; min-width: 100%; }
  th { position: sticky; top: 0; background: #37474f; color: #fff; text-align: left; padding: 8px 10px; font-weight: 600; z-index: 1; }
  td { padding: 6px 10px; border-bottom: 1px solid #eee; vertical-align: top; max-width: 420px; word-break: break-word; }
  tr.row-apply { background: #e8f5e9; }
  tr.row-review { background: #fffde7; }
  tr.row-skip { background: #f5f5f5; }
  tr.row-other { background: #fff; }
</style>
</head>
<body>
<h1>Разбор плана переноса (MediaInboxToolkit)</h1>
<p class="meta">Исходный CSV: $(Escape-HtmlCell $CsvPath)<br/>
Сгенерировано: $(Escape-HtmlCell (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))</p>

<div class="legend">
  <span class="lg-apply">APPLY — к переносу (авто или вы подтвердили)</span>
  <span class="lg-review">REVIEW — нужна ваша проверка</span>
  <span class="lg-skip">SKIP — не переносим</span>
</div>

<div class="hint">
  <strong>Ручная правка в Excel / LibreOffice:</strong> откройте одноимённый файл <code>.for-human.csv</code> (если создавали через Prepare).
  Колонки <strong>HumanOverride</strong> (пусто / APPLY / SKIP / REVIEW), <strong>HumanComment</strong>, <strong>HumanDestOverride</strong> (полный путь назначения, если переопределяете).
  При переносе скрипт <code>Invoke-MediaInboxApplyReviewedCsv.ps1</code> учитывает HumanOverride и HumanDestOverride.
</div>

<ul class="stats">
  <li>Всего строк: <strong>$($rows.Count)</strong></li>
  <li>APPLY: <strong>$($byDec['APPLY'])</strong></li>
  <li>REVIEW: <strong>$($byDec['REVIEW'])</strong></li>
  <li>SKIP: <strong>$($byDec['SKIP'])</strong></li>
</ul>

<h2>Сначала проверь (REVIEW) — $($reviewRows.Count) строк</h2>
<div class="wrap">
<table>
<thead>$thead</thead>
<tbody>
$(Build-TableRows $reviewRows)
</tbody>
</table>
</div>

<h2>APPLY — $($applyRows.Count) строк</h2>
<div class="wrap">
<table>
<thead>$thead</thead>
<tbody>
$(Build-TableRows $applyRows)
</tbody>
</table>
</div>

<h2>SKIP — $($skipRows.Count) строк</h2>
<div class="wrap">
<table>
<thead>$thead</thead>
<tbody>
$(Build-TableRows $skipRows)
</tbody>
</table>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtmlPath, $html, [System.Text.UTF8Encoding]::new($true))
Write-Host "HTML report: $OutHtmlPath"
