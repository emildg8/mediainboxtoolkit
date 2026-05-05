#requires -Version 5.1
# Минимальный GUI (MVP): пути, пресет политики, скелет папок, DryRun/Apply/UseTmdb, запуск MediaInboxToolkit.ps1.
[CmdletBinding()]
param(
    [string]$ToolkitRoot = ''
)

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
    $ToolkitRoot = $PSScriptRoot
}
$ToolkitRoot = $ToolkitRoot.Trim().TrimEnd('\', '/')
$launcher = Join-Path $ToolkitRoot 'MediaInboxToolkit.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "MediaInboxToolkit.ps1 not found: $launcher"
}

$pathExample = Join-Path $ToolkitRoot 'sort-inbox.example.json'
$pathVideoAscii = Join-Path $ToolkitRoot 'sort-inbox.video-under-sort.example.json'
$pathVideoCyr = Join-Path $ToolkitRoot 'sort-inbox.video-under-sort.cyrillic.example.json'
$skeletonPs1 = Join-Path $ToolkitRoot 'New-MediaInboxDestinationSkeleton.ps1'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'MediaInboxToolkit'
$form.Size = New-Object System.Drawing.Size(560, 540)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$y = 16
$lblIn = New-Object System.Windows.Forms.Label
$lblIn.Text = 'Inbox (папка с загрузками):'
$lblIn.Location = New-Object System.Drawing.Point(16, $y)
$lblIn.AutoSize = $true
$form.Controls.Add($lblIn)
$y += 28
$tbInbox = New-Object System.Windows.Forms.TextBox
$tbInbox.Location = New-Object System.Drawing.Point(16, $y)
$tbInbox.Size = New-Object System.Drawing.Size(500, 24)
$form.Controls.Add($tbInbox)
$y += 40
$lblPol = New-Object System.Windows.Forms.Label
$lblPol.Text = 'Политика JSON (пусто = sort-inbox.example.json):'
$lblPol.Location = New-Object System.Drawing.Point(16, $y)
$lblPol.AutoSize = $true
$form.Controls.Add($lblPol)
$y += 28
$tbPolicy = New-Object System.Windows.Forms.TextBox
$tbPolicy.Location = New-Object System.Drawing.Point(16, $y)
$tbPolicy.Size = New-Object System.Drawing.Size(500, 24)
$tbPolicy.Text = $pathExample
$form.Controls.Add($tbPolicy)
$y += 32
$lblPreset = New-Object System.Windows.Forms.Label
$lblPreset.Text = 'Пресет политики (подставить путь в поле выше):'
$lblPreset.Location = New-Object System.Drawing.Point(16, $y)
$lblPreset.AutoSize = $true
$form.Controls.Add($lblPreset)
$y += 24
$cbPreset = New-Object System.Windows.Forms.ComboBox
$cbPreset.DropDownStyle = 'DropDownList'
$cbPreset.Location = New-Object System.Drawing.Point(16, $y)
$cbPreset.Size = New-Object System.Drawing.Size(500, 24)
[void]$cbPreset.Items.Add('— не менять путь —')
[void]$cbPreset.Items.Add('Sort\Video: ASCII (series/movies/…)')
[void]$cbPreset.Items.Add('Sort\Video: кириллица (Сериалы/Фильмы/…)')
[void]$cbPreset.Items.Add('Нейтральный sort-inbox.example.json')
$cbPreset.SelectedIndex = 0
$form.Controls.Add($cbPreset)
$y += 32
$btnSkel = New-Object System.Windows.Forms.Button
$btnSkel.Text = 'Создать скелет папок (destinations + skeletonExtraRelatives)'
$btnSkel.Location = New-Object System.Drawing.Point(16, $y)
$btnSkel.Size = New-Object System.Drawing.Size(500, 30)
$form.Controls.Add($btnSkel)
$y += 42
$cbTmdb = New-Object System.Windows.Forms.CheckBox
$cbTmdb.Text = 'UseTmdb (TMDB_API_KEY)'
$cbTmdb.Location = New-Object System.Drawing.Point(16, $y)
$cbTmdb.AutoSize = $true
$form.Controls.Add($cbTmdb)
$y += 32
$cbDry = New-Object System.Windows.Forms.CheckBox
$cbDry.Text = 'DryRun (только план, без переноса)'
$cbDry.Checked = $true
$cbDry.Location = New-Object System.Drawing.Point(16, $y)
$cbDry.AutoSize = $true
$form.Controls.Add($cbDry)
$y += 32
$cbApply = New-Object System.Windows.Forms.CheckBox
$cbApply.Text = 'Apply (перенос файлов)'
$cbApply.Location = New-Object System.Drawing.Point(16, $y)
$cbApply.AutoSize = $true
$form.Controls.Add($cbApply)
$y += 44
$btn = New-Object System.Windows.Forms.Button
$btn.Text = 'Запустить'
$btn.Location = New-Object System.Drawing.Point(16, $y)
$btn.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btn)
$y += 48
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(16, $y)
$txtLog.Size = New-Object System.Drawing.Size(500, 110)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog)

$cbPreset.Add_SelectedIndexChanged({
        switch ($cbPreset.SelectedIndex) {
            1 { $tbPolicy.Text = $pathVideoAscii }
            2 { $tbPolicy.Text = $pathVideoCyr }
            3 { $tbPolicy.Text = $pathExample }
            default { }
        }
    })

$btnSkel.Add_Click({
        $pol = $tbPolicy.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($pol)) {
            $pol = $pathExample
        }
        if (-not (Test-Path -LiteralPath $pol)) {
            [System.Windows.Forms.MessageBox]::Show("Файл политики не найден:`n$pol", 'MediaInboxToolkit') | Out-Null
            return
        }
        if (-not (Test-Path -LiteralPath $skeletonPs1)) {
            [System.Windows.Forms.MessageBox]::Show("Не найден: $skeletonPs1", 'MediaInboxToolkit') | Out-Null
            return
        }
        $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$skeletonPs1`" -PolicyPath `"$pol`""
        $txtLog.Text = "Скелет: powershell $argLine`r`n..."
        [System.Windows.Forms.Application]::DoEvents()
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $skeletonPs1,
                    '-PolicyPath', $pol
                ) -PassThru -Wait -NoNewWindow `
                -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            $code = $p.ExitCode
            $so = if (Test-Path -LiteralPath $tmpOut) { Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 } else { '' }
            $se = if (Test-Path -LiteralPath $tmpErr) { Get-Content -LiteralPath $tmpErr -Raw -Encoding UTF8 } else { '' }
            $txtLog.Text = "Скелет exit: $code`r`n$so`r`n$se"
        } catch {
            $txtLog.Text = 'Ошибка скелета: ' + $_.Exception.Message
        } finally {
            Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
        }
    })

$btn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($tbInbox.Text)) {
            [System.Windows.Forms.MessageBox]::Show('Укажите путь к inbox.', 'MediaInboxToolkit') | Out-Null
            return
        }
        $pol = $tbPolicy.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($pol)) {
            $pol = $pathExample
        }
        $args = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
            '-InboxPath', $tbInbox.Text.Trim(),
            '-PolicyPath', $pol,
            '-SkipAutoSync'
        )
        if ($cbTmdb.Checked) { $args += '-UseTmdb' }
        if ($cbApply.Checked) { $args += '-Apply' }
        elseif ($cbDry.Checked) { $args += '-DryRun' }
        $argLine = ($args | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
        $txtLog.Text = "Запуск: powershell $argLine`r`n..."
        [System.Windows.Forms.Application]::DoEvents()
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -Wait -NoNewWindow `
                -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            $code = $p.ExitCode
            $so = if (Test-Path -LiteralPath $tmpOut) { Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 } else { '' }
            $se = if (Test-Path -LiteralPath $tmpErr) { Get-Content -LiteralPath $tmpErr -Raw -Encoding UTF8 } else { '' }
            $txtLog.Text = "Exit: $code`r`n$so`r`n$se"
        } catch {
            $txtLog.Text = 'Ошибка: ' + $_.Exception.Message
        } finally {
            Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
        }
    })

[System.Windows.Forms.Application]::Run($form)
