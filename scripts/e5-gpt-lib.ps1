<#
.SYNOPSIS
  用纯 PowerShell 编辑手机 eMMC 的 GPT（不需要 Python、Node 或任何外部工具）。

.DESCRIPTION
  把 userdata 缩到指定扇区数，并在其后的空闲空间创建 e5root 分区，
  供 e5-linux 的 boot/init 直接启动（它按 GPT 分区名 e5root 查找）。
  主 GPT 与备份 GPT 都会重写并重算 CRC32。

  只读写 17 KiB 的 GPT 区域，不碰数据区。

.PARAMETER UserdataSectors  缩容后 userdata 的扇区数
.PARAMETER Name             新分区名，默认 e5root
.PARAMETER AdbSerial        adb 设备序列号（可选）
.PARAMETER DryRun           只打印计划，不写设备
.PARAMETER PrintOffset      只打印指定分区的起始字节并退出
#>
[CmdletBinding()]
param(
    [long]$UserdataSectors = 0,
    [string]$Name = 'e5root',
    [string]$AdbSerial = '',
    [switch]$DryRun,
    [string]$PrintOffset = ''
)

$ErrorActionPreference = 'Stop'
$Sector = 512
$EntrySize = 128
$EntriesSectors = 32          # 128 项 × 128 B = 16 KiB
# Linux filesystem 分区类型 GUID（磁盘字节序）
$LinuxFsType = [byte[]]@(0xAF,0x3D,0xC6,0x0F,0x83,0x84,0x72,0x47,0x8E,0x79,0x3D,0x69,0xD8,0x47,0x7D,0xE4)
$ZeroGuid = [byte[]]::new(16)

function Invoke-Adb([string]$ArgLine) {
    $out = & cmd /c "adb $ArgLine 2>&1" | Out-String
    return $out.Trim()
}
function Invoke-Su([string]$Cmd) { return Invoke-Adb ('shell su -c "' + $Cmd + '"') }

function Read-Device {
    param([int]$Skip, [int]$Count)
    $b64 = Invoke-Su "dd if=/dev/block/mmcblk0 bs=512 skip=$Skip count=$Count 2>/dev/null | base64"
    $b64 = ($b64 -replace '\s', '')
    if (-not $b64) { throw "读取扇区 $Skip 失败" }
    return [Convert]::FromBase64String($b64)
}
function Write-Device {
    param([int]$Skip, [byte[]]$Data)
    $b64 = [Convert]::ToBase64String($Data)
    # base64 可能较长，分段写入再拼接到一次 dd 里
    $tmp = '/data/local/tmp/.e5-gpt.b64'
    Invoke-Su "rm -f $tmp"
    for ($i = 0; $i -lt $b64.Length; $i += 3000) {
        $chunk = $b64.Substring($i, [Math]::Min(3000, $b64.Length - $i))
        Invoke-Su "echo -n $chunk >> $tmp" | Out-Null
    }
    $r = Invoke-Su "base64 -d $tmp | dd of=/dev/block/mmcblk0 bs=512 seek=$Skip conv=notrunc 2>&1 | tail -1"
    Invoke-Su "rm -f $tmp" | Out-Null
    return $r
}

function Get-U16 { param([byte[]]$B, [int]$O) return [BitConverter]::ToUInt16($B, $O) }
function Get-U32 { param([byte[]]$B, [int]$O) return [BitConverter]::ToUInt32($B, $O) }
function Get-U64 { param([byte[]]$B, [int]$O) return [BitConverter]::ToUInt64($B, $O) }
function Set-U32 { param([byte[]]$B, [int]$O, [uint32]$V) [Array]::Copy([BitConverter]::GetBytes($V), 0, $B, $O, 4) }
function Set-U64 { param([byte[]]$B, [int]$O, [uint64]$V) [Array]::Copy([BitConverter]::GetBytes($V), 0, $B, $O, 8) }

function Get-Crc32 {
    param([byte[]]$Data)
    # 标准 CRC-32（与 Python zlib.crc32 一致）
    $table = Get-Crc32Table
    $MASK = [uint64]4294967295      # 0xFFFFFFFF
    [uint64]$crc = $MASK
    foreach ($b in $Data) {
        $crc = [uint64]($table[[int](($crc -bxor $b) -band 0xFF)] -bxor ($crc -shr 8))
        $crc = $crc -band $MASK
    }
    return [uint32]($crc -bxor $MASK)
}
$script:CrcTable = $null
function Get-Crc32Table {
    if ($script:CrcTable) { return $script:CrcTable }
    $POLY = [uint64]3988292384          # 0xEDB88320
    $t = New-Object 'uint32[]' 256
    for ($n = 0; $n -lt 256; $n++) {
        [uint64]$c = [uint64]$n
        for ($k = 0; $k -lt 8; $k++) {
            if ($c -band 1) { $c = [uint64]($POLY -bxor ($c -shr 1)) }
            else { $c = [uint64]($c -shr 1) }
        }
        $t[$n] = [uint32]($c -band 0xFFFFFFFF)
    }
    $script:CrcTable = $t
    return $t
}

function Get-Entries {
    param([byte[]]$Raw)
    $out = @()
    $count = [int]($Raw.Length / $EntrySize)
    for ($i = 0; $i -lt $count; $i++) {
        $o = $i * $EntrySize
        $type = [byte[]]::new(16)
        [Array]::Copy($Raw, $o, $type, 0, 16)
        if (($type | Where-Object { $_ -ne 0 }).Count -eq 0) { $out += $null; continue }
        $first = [long](Get-U64 $Raw ($o + 32))
        $last = [long](Get-U64 $Raw ($o + 40))
        $nameBytes = [byte[]]::new(72)
        [Array]::Copy($Raw, $o + 56, $nameBytes, 0, 72)
        $nm = [Text.Encoding]::Unicode.GetString($nameBytes).TrimEnd([char]0)
        $out += [pscustomobject]@{ Index = $i; Type = $type; First = $first; Last = $last; Name = $nm }
    }
    return $out
}

function New-EntryBytes {
    param([byte[]]$Type, [long]$First, [long]$Last, [string]$Name)
    $e = [byte[]]::new($EntrySize)
    [Array]::Copy($Type, 0, $e, 0, 16)
    [Array]::Copy($ZeroGuid, 0, $e, 16, 16)
    Set-U64 $e 32 ([uint64]$First)
    Set-U64 $e 40 ([uint64]$Last)
    $nb = [Text.Encoding]::Unicode.GetBytes($Name)
    $n = [Math]::Min($nb.Length, 72)
    [Array]::Copy($nb, 0, $e, 56, $n)
    return $e
}

function Repair-Header {
    param([byte[]]$Head, [byte[]]$Entries)
    $h = [byte[]]::new($Head.Length)
    [Array]::Copy($Head, $h, $Head.Length)
    Set-U32 $h 88 (Get-Crc32 $Entries)      # entries CRC
    Set-U32 $h 16 ([uint32]0)                # header CRC 字段先清零
    $head92 = [byte[]]::new(92)
    [Array]::Copy($h, 0, $head92, 0, 92)
    Set-U32 $h 16 (Get-Crc32 $head92)
    return $h
}

# ---------------------------------------------------------------- 