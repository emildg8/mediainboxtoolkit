#requires -Version 5.1
<#
.SYNOPSIS
  Создаёт корневые папки из policy.destinations и (опционально) folders.skeletonExtraRelatives.
.NOTES
  Политика: folders.skeletonProfile (ascii|cyrillic) — только метка для UI/доков; пути задают destinations.
  folders.workspaceSeriesToolkitSubfolders — не создаёт отдельных корней (это подпапки под теми же корнями), движок сортировки их не читает.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$PolicyPath,
    [switch]$SkipSkeletonExtras
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PolicyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PolicyPath)
if (-not (Test-Path -LiteralPath $PolicyPath)) { throw "Policy not found: $PolicyPath" }

$policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nasRoot = [string]$policy.nasShareRoot
if ([string]::IsNullOrWhiteSpace($nasRoot)) { throw 'Policy requires nasShareRoot.' }
if (-not ($policy.PSObject.Properties.Name -contains 'destinations') -or $null -eq $policy.destinations) {
    throw 'Policy requires destinations object.'
}

function Expand-MitPolicyPath {
    param([string]$NasRoot, [string]$Relative)
    $rel = ($Relative -replace '/', '\').TrimStart('\')
    return (Join-Path -Path $NasRoot -ChildPath $rel)
}

$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Add-MitSkeletonDir {
    param([string]$FullPath)
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return }
    if (-not $seen.Add($FullPath)) { return }
    if ($PSCmdlet.ShouldProcess($FullPath, 'Create directory')) {
        if (-not (Test-Path -LiteralPath $FullPath)) {
            New-Item -ItemType Directory -Path $FullPath -Force | Out-Null
        }
    }
}

foreach ($dp in $policy.destinations.PSObject.Properties) {
    $full = Expand-MitPolicyPath -NasRoot $nasRoot -Relative ([string]$dp.Value)
    Add-MitSkeletonDir -FullPath $full
}

if (-not $SkipSkeletonExtras -and ($policy.PSObject.Properties.Name -contains 'folders') -and $null -ne $policy.folders) {
    $fd = $policy.folders
    if ($fd.PSObject.Properties.Name -contains 'skeletonExtraRelatives' -and $null -ne $fd.skeletonExtraRelatives) {
        foreach ($rel in @($fd.skeletonExtraRelatives)) {
            if ($null -eq $rel) { continue }
            $s = [string]$rel
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            Add-MitSkeletonDir -FullPath (Expand-MitPolicyPath -NasRoot $nasRoot -Relative $s)
        }
    }
}

Write-Host "Skeleton paths ensured: $($seen.Count) (destinations + extras). Policy: $PolicyPath"
