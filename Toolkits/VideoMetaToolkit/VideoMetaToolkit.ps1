#requires -Version 5.1
<#
.SYNOPSIS
  Заготовка launcher для будущего модуля VideoMetaToolkit.
.DESCRIPTION
  План: генерация описаний, постеров, актёров и sidecar-метаданных рядом с медиа,
  с возможностью агрегации в индекс для UI.
#>
[CmdletBinding()]
param(
    [ValidateSet('Plan', 'BuildIndex', 'ExportSidecars')]
    [string]$Mode = 'Plan',
    [string]$RootPath = '',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "VideoMetaToolkit scaffold"
Write-Host "Mode: $Mode  RootPath: $RootPath  DryRun: $DryRun"
Write-Host "TODO: implementation starts in next iteration."
