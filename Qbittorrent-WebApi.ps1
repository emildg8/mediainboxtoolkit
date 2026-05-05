#requires -Version 5.1
# Опциональное обогащение путей через qBittorrent Web API v2 (настраиваемый base URL — без хардкода хоста).

Set-StrictMode -Version Latest

function Get-QbitObjectString {
    param(
        $Object,
        [string]$PropertyName,
        [string]$Default = ''
    )
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $p) { return $Default }
    return [string]$p.Value
}

function Initialize-MediaInboxQbitTlsBypass {
    if (-not ([System.Management.Automation.PSTypeName]'MediaInboxTrustAllCerts' -as [type])) {
        $def = @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.Net.Security;
public class MediaInboxTrustAllCerts {
    public static void Enable() {
        ServicePointManager.ServerCertificateValidationCallback =
            delegate { return true; };
    }
}
'@
        Add-Type -TypeDefinition $def -ErrorAction Stop
    }
    [MediaInboxTrustAllCerts]::Enable()
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

function Normalize-MediaInboxPathKey {
    param([string]$FullPath)
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return '' }
    try {
        $x = [System.IO.Path]::GetFullPath($FullPath)
    } catch {
        $x = $FullPath
    }
    return $x.TrimEnd('\').ToLowerInvariant()
}

function Connect-MediaInboxQbitWebApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebUiBaseUrl,
        [string]$Username = '',
        [string]$Password = '',
        [switch]$SkipCertificateCheck
    )
    $base = $WebUiBaseUrl.TrimEnd('/')
    if ($SkipCertificateCheck) {
        Initialize-MediaInboxQbitTlsBypass
    }
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    # Если в qBittorrent отключена аутентификация Web UI, /auth/login не нужен — достаточно сессии.
    $probeUrl = "$base/api/v2/app/webapiVersion"
    try {
        $probe = Invoke-WebRequest -Uri $probeUrl -WebSession $session -UseBasicParsing -TimeoutSec 25
        if ($probe.StatusCode -eq 200) {
            return [pscustomobject]@{
                BaseUrl = $base
                Session = $session
            }
        }
    } catch {
        # Требуется логин или другая ошибка — пробуем auth/login.
    }

    $loginUrl = "$base/api/v2/auth/login"
    $pair = 'username={0}&password={1}' -f (
        [System.Uri]::EscapeDataString($Username),
        [System.Uri]::EscapeDataString($Password)
    )
    $resp = Invoke-WebRequest -Uri $loginUrl -Method Post -Body $pair -WebSession $session -UseBasicParsing -TimeoutSec 45 -ContentType 'application/x-www-form-urlencoded'
    if ($resp.StatusCode -ne 200) {
        throw "qBittorrent auth HTTP $($resp.StatusCode)"
    }
    $body = [string]$resp.Content
    if ($body -eq 'Fails.') {
        throw 'qBittorrent auth/login returned Fails. (wrong user/password or Web UI API disabled).'
    }
    return [pscustomobject]@{
        BaseUrl = $base
        Session = $session
    }
}

function Get-MediaInboxQbitTorrentsRaw {
    param(
        [Parameter(Mandatory = $true)]
        $Connection
    )
    $url = "$($Connection.BaseUrl)/api/v2/torrents/info"
    $r = Invoke-WebRequest -Uri $url -WebSession $Connection.Session -UseBasicParsing -TimeoutSec 120
    if ([string]::IsNullOrWhiteSpace($r.Content)) { return @() }
    return @($r.Content | ConvertFrom-Json)
}

function Get-MediaInboxQbitTorrentFilesRaw {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        [Parameter(Mandatory = $true)]
        [string]$Hash
    )
    $h = [System.Uri]::EscapeDataString($Hash)
    $url = "$($Connection.BaseUrl)/api/v2/torrents/files?hash=$h"
    $r = Invoke-WebRequest -Uri $url -WebSession $Connection.Session -UseBasicParsing -TimeoutSec 90
    if ([string]::IsNullOrWhiteSpace($r.Content)) { return @() }
    return @($r.Content | ConvertFrom-Json)
}

function Build-MediaInboxQbitFullPathIndex {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        [Parameter(Mandatory = $true)]
        [hashtable]$InfoSha1HexToHintIndex
    )
    $map = @{}
    $rows = Get-MediaInboxQbitTorrentsRaw -Connection $Connection
    foreach ($t in $rows) {
        $h = Get-QbitObjectString $t 'hash'
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        if (-not $InfoSha1HexToHintIndex.ContainsKey($h)) { continue }
        $hintIx = $InfoSha1HexToHintIndex[$h]
        $save = Get-QbitObjectString $t 'save_path'
        if ([string]::IsNullOrWhiteSpace($save)) { continue }

        $files = Get-MediaInboxQbitTorrentFilesRaw -Connection $Connection -Hash $h
        foreach ($f in $files) {
            $rel = (Get-QbitObjectString $f 'name') -replace '/', [System.IO.Path]::DirectorySeparatorChar
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            try {
                $full = [System.IO.Path]::GetFullPath((Join-Path -Path $save -ChildPath $rel))
            } catch {
                continue
            }
            $nk = Normalize-MediaInboxPathKey $full
            if (-not [string]::IsNullOrWhiteSpace($nk)) {
                $map[$nk] = $hintIx
            }
        }

        $cp = Get-QbitObjectString $t 'content_path'
        if (-not [string]::IsNullOrWhiteSpace($cp)) {
            try {
                $fullCp = [System.IO.Path]::GetFullPath($cp)
                $nk2 = Normalize-MediaInboxPathKey $fullCp
                if (-not [string]::IsNullOrWhiteSpace($nk2)) {
                    $map[$nk2] = $hintIx
                }
            } catch { }
        }
    }
    return $map
}
