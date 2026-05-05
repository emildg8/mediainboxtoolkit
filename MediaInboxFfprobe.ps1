#requires -Version 5.1
# Длительность файла (сек, округление) через ffprobe — для tie-break и проверок.

Set-StrictMode -Version Latest

function Get-MitVideoDurationSeconds {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath
    )
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $null }
    $candidates = [System.Collections.Generic.List[string]]::new()
    [void]$candidates.Add('ffprobe')
    $wingetFfprobe = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Microsoft\WinGet\Links\ffprobe.exe'
    if (Test-Path -LiteralPath $wingetFfprobe) { [void]$candidates.Add($wingetFfprobe) }
    $pf86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    foreach ($dir in @(
            $(Join-Path ${env:ProgramFiles} 'ffmpeg\bin'),
            $(if ($pf86) { Join-Path $pf86 'ffmpeg\bin' } else { '' }),
            'C:\ffmpeg\bin'
        )) {
        if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
        $p = Join-Path $dir 'ffprobe.exe'
        if (Test-Path -LiteralPath $p) { [void]$candidates.Add($p) }
    }
    foreach ($exe in $candidates) {
        $psi = $null
        if ($exe -eq 'ffprobe') {
            $cmdFf = Get-Command ffprobe -ErrorAction SilentlyContinue
            if ($cmdFf) { $psi = $cmdFf.Source }
        }
        elseif (Test-Path -LiteralPath $exe) { $psi = $exe }
        if ([string]::IsNullOrWhiteSpace($psi)) { continue }
        try {
            $args = @('-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', $LiteralPath)
            $raw = & $psi @args 2>$null
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $d = 0.0
            if (-not [double]::TryParse(($raw -replace ',', '.').Trim(), [ref]$d)) { continue }
            if ($d -gt 0 -and $d -lt 864000) { return [int][math]::Round($d) }
        }
        catch { }
    }
    return $null
}
