#requires -Version 5.1
# Minimal .torrent (bencode) helpers for MediaInboxToolkit — info-dict SHA1 + video file leaves.

Set-StrictMode -Version Latest

function Read-BencodeInteger {
    param([byte[]]$Bytes, [ref]$Pos)
    if ($Bytes[$Pos.Value] -ne [byte][char]'i') { throw "bencode: expected i at $($Pos.Value)" }
    $Pos.Value++
    $sb = New-Object System.Text.StringBuilder
    while ($Bytes[$Pos.Value] -ne [byte][char]'e') {
        [void]$sb.Append([char]$Bytes[$Pos.Value])
        $Pos.Value++
    }
    $Pos.Value++
    return [long]$sb.ToString()
}

function Read-BencodeByteString {
    param([byte[]]$Bytes, [ref]$Pos)
    $sb = New-Object System.Text.StringBuilder
    while ($Bytes[$Pos.Value] -ne [byte][char]':') {
        [void]$sb.Append([char]$Bytes[$Pos.Value])
        $Pos.Value++
    }
    $Pos.Value++
    $len = [int]$sb.ToString()
    if ($len -lt 0) { throw "bencode: negative string length" }
    $slice = New-Object byte[] $len
    if ($len -gt 0) {
        [Array]::Copy($Bytes, $Pos.Value, $slice, 0, $len)
        $Pos.Value += $len
    }
    return , $slice
}

function Read-BencodeValue {
    param([byte[]]$Bytes, [ref]$Pos)
    $mark = [char]$Bytes[$Pos.Value]
    switch ($mark) {
        'i' { return Read-BencodeInteger -Bytes $Bytes -Pos $Pos }
        'l' {
            $Pos.Value++
            $list = [System.Collections.ArrayList]::new()
            while ([char]$Bytes[$Pos.Value] -ne 'e') {
                [void]$list.Add((Read-BencodeValue -Bytes $Bytes -Pos $Pos))
            }
            $Pos.Value++
            return $list
        }
        'd' {
            $Pos.Value++
            $ht = @{}
            while ([char]$Bytes[$Pos.Value] -ne 'e') {
                $keyBytes = Read-BencodeByteString -Bytes $Bytes -Pos $Pos
                $key = [System.Text.Encoding]::UTF8.GetString($keyBytes)
                $ht[$key] = Read-BencodeValue -Bytes $Bytes -Pos $Pos
            }
            $Pos.Value++
            return $ht
        }
        default {
            if ($mark -ge '0' -and $mark -le '9') {
                return Read-BencodeByteString -Bytes $Bytes -Pos $Pos
            }
            throw "bencode: unexpected byte '$mark' at $($Pos.Value)"
        }
    }
}

function Write-BencodeObject {
    param(
        $Obj,
        [System.IO.MemoryStream]$Stream
    )
    if ($Obj -is [byte[]]) {
        $lenB = [System.Text.Encoding]::ASCII.GetBytes(('{0}:' -f $Obj.Length))
        $Stream.Write($lenB, 0, $lenB.Length)
        if ($Obj.Length -gt 0) {
            $Stream.Write($Obj, 0, $Obj.Length)
        }
    }
    elseif ($Obj -is [long] -or $Obj -is [int]) {
        $s = [System.Text.Encoding]::ASCII.GetBytes(('i{0}e' -f $Obj))
        $Stream.Write($s, 0, $s.Length)
    }
    elseif ($Obj -is [System.Collections.ArrayList]) {
        $Stream.WriteByte([byte][char]'l')
        foreach ($x in $Obj) {
            Write-BencodeObject -Obj $x -Stream $Stream
        }
        $Stream.WriteByte([byte][char]'e')
    }
    elseif ($Obj -is [System.Collections.IList]) {
        $Stream.WriteByte([byte][char]'l')
        foreach ($x in $Obj) {
            Write-BencodeObject -Obj $x -Stream $Stream
        }
        $Stream.WriteByte([byte][char]'e')
    }
    elseif ($Obj -is [hashtable]) {
        $Stream.WriteByte([byte][char]'d')
        # .torrent info keys are ASCII; Sort-Object совпадает с лексикографическим порядком байт ключей.
        $keys = @($Obj.Keys | Sort-Object)
        foreach ($k in $keys) {
            $kb = [System.Text.Encoding]::UTF8.GetBytes([string]$k)
            Write-BencodeObject -Obj $kb -Stream $Stream
            Write-BencodeObject -Obj $Obj[$k] -Stream $Stream
        }
        $Stream.WriteByte([byte][char]'e')
    }
    else {
        throw "Write-BencodeObject: unsupported type $($Obj.GetType().FullName)"
    }
}

function Get-TorrentRootDict {
    param([string]$LiteralPath)
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $pos = [ref]0
    $root = Read-BencodeValue -Bytes $bytes -Pos $pos
    if (-not ($root -is [hashtable])) { throw "torrent root is not a dict: $LiteralPath" }
    return [hashtable]$root
}

function Get-TorrentHintMeta {
    param([string]$LiteralPath)
    try {
        $root = Get-TorrentRootDict -LiteralPath $LiteralPath
        if (-not $root.ContainsKey('info')) { return $null }
        $info = $root['info']
        if (-not ($info -is [hashtable])) { return $null }
        $ms = New-Object System.IO.MemoryStream
        Write-BencodeObject -Obj $info -Stream $ms
        $infoBytes = $ms.ToArray()
        $sha1 = [System.Security.Cryptography.SHA1]::Create().ComputeHash($infoBytes)
        $shaHex = -join ($sha1 | ForEach-Object { $_.ToString('x2') })
        $leaves = Get-TorrentVideoLeaves -InfoDict $info
        $blob = Get-TorrentMetainfoTextBlob -InfoDict $info
        return [pscustomobject]@{
            InfoSha1Hex = $shaHex
            VideoLeaves = $leaves
            MetaBlob    = $blob
        }
    } catch {
        return $null
    }
}

function Get-TorrentInfoSha1Hex {
    param([string]$LiteralPath)
    $m = Get-TorrentHintMeta -LiteralPath $LiteralPath
    if ($null -eq $m) { throw "cannot read info: $LiteralPath" }
    return [string]$m.InfoSha1Hex
}

function Test-VideoExtension {
    param([string]$Ext)
    $e = $Ext.TrimStart('.').ToLowerInvariant()
    return $e -in @('mkv', 'mp4', 'avi', 'm4v', 'mov', 'webm', 'mpeg', 'mpg', 'ts', 'm2ts', 'wmv', 'flv')
}

function Get-TorrentVideoLeaves {
    param([hashtable]$InfoDict)
    $leaves = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $InfoDict) { return @() }

    if ($InfoDict.ContainsKey('files')) {
        $files = $InfoDict['files']
        foreach ($fd in $files) {
            if (-not ($fd -is [hashtable])) { continue }
            if (-not $fd.ContainsKey('path')) { continue }
            $pathParts = $fd['path']
            if ($null -eq $pathParts) { continue }
            $leaf = ''
            if ($pathParts -is [byte[]]) {
                $rel = [System.Text.Encoding]::UTF8.GetString($pathParts)
                $rel = $rel -replace '/', [System.IO.Path]::DirectorySeparatorChar
                $leaf = [System.IO.Path]::GetFileName($rel)
            }
            else {
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($seg in $pathParts) {
                    if ($seg -is [byte[]]) {
                        [void]$parts.Add([System.Text.Encoding]::UTF8.GetString($seg))
                    }
                    else {
                        [void]$parts.Add([string]$seg)
                    }
                }
                if ($parts.Count -eq 0) { continue }
                $leaf = $parts[$parts.Count - 1]
            }
            if (-not [string]::IsNullOrWhiteSpace($leaf) -and (Test-VideoExtension -Ext ([System.IO.Path]::GetExtension($leaf)))) {
                [void]$leaves.Add($leaf)
            }
        }
    }
    else {
        if (-not $InfoDict.ContainsKey('name')) { return @() }
        $nameB = $InfoDict['name']
        if (-not ($nameB -is [byte[]])) { return @() }
        $name = [System.Text.Encoding]::UTF8.GetString($nameB)
        if (Test-VideoExtension -Ext ([System.IO.Path]::GetExtension($name))) {
            [void]$leaves.Add([System.IO.Path]::GetFileName($name))
        }
    }
    return @($leaves)
}

function Get-TorrentMetainfoTextBlob {
    param([hashtable]$InfoDict)
    if ($null -eq $InfoDict) { return '' }
    $sb = New-Object System.Text.StringBuilder
    if ($InfoDict.ContainsKey('name')) {
        $nb = $InfoDict['name']
        if ($nb -is [byte[]]) {
            [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($nb))
            [void]$sb.Append(' ')
        }
    }
    foreach ($leaf in (Get-TorrentVideoLeaves -InfoDict $InfoDict)) {
        [void]$sb.Append($leaf)
        [void]$sb.Append(' ')
    }
    return $sb.ToString().Trim()
}
