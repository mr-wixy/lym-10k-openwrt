<#
.SYNOPSIS
  一键把 e5-linux（OpenWrt）装进 LYM-10K 机身存储，与 Android 双系统共存。

.DESCRIPTION
  前置：已解锁 bootloader、已装 Magisk 并允许 shell 使用 root、设备运行 Android、adb 可用。

  流程：
    1. 校验设备 / root / 载荷
    2. 在线缩容 Android /data（默认 18 GiB，数据保留）
    3. 改 GPT：userdata 缩到与文件系统一致，其后新建 e5root 分区
    4. 把预置了 part-root 标记的 rootfs 镜像写入 e5root
    5. 安装 Magisk 模块（Android 里点 Action 切回 Linux）
    6. 写 boot_b、武装 slot b，重启进入 e5-linux

.PARAMETER PayloadDir  载荷目录，默认脚本同级 payload/
.PARAMETER TargetGiB   缩容后 /data 大小，默认 18
.PARAMETER AdbSerial   多设备时指定序列号
.PARAMETER DryRun      只检查并打印计划，不写设备
#>
[CmdletBinding()]
param(
    [string]$PayloadDir = '',
    [int]$TargetGiB = 18,
    [string]$AdbSerial = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

# ===================== GPT 编辑（纯 PowerShell，无需 Python 等外部环境）=====================
# 只读写 17 KiB 的 GPT 区域；主 GPT 与备份 GPT 都会重写并重算 CRC32。
# CRC32 与解析逻辑已用 Python zlib 交叉验证：逐字节一致。
$script:AdbTarget = $null

function Invoke-Adb([string]$ArgLine) {
    $t = if ($script:AdbTarget) { "adb -s $($script:AdbTarget) $ArgLine" } else { "adb $ArgLine" }
    $out = & cmd /c "$t 2>&1" | Out-String
    return $out.Trim()
}
function Invoke-Su([string]$Cmd) { return Invoke-Adb ('shell su -c "' + $Cmd + '"') }

$Sector = 512
$EntrySize = 128
$EntriesSectors = 32          # 128 项 × 128 B = 16 KiB
# Linux filesystem 分区类型 GUID（磁盘字节序）
$LinuxFsType = [byte[]]@(0xAF,0x3D,0xC6,0x0F,0x83,0x84,0x72,0x47,0x8E,0x79,0x3D,0x69,0xD8,0x47,0x7D,0xE4)
$ZeroGuid = [byte[]]::new(16)


function Read-Device {
    param([int]$Skip, [int]$Count)
    $b64 = Invoke-Su "dd if=/dev/block/mmcblk0 bs=512 skip=$Skip count=$Count 2>/dev/null | base64"
    $b64 = ($b64 -replace '\s', '')
    if (-not $b64) { throw "读取扇区 $Skip 失败" }
    return [Convert]::FromBase64String($b64)
}
function Write-Device {
    param([int]$Skip, [byte[]]$Data)
    # 走 adb push 传文件：不依赖设备端 shell 的 echo。
    # Android 的 mksh 里 `echo -n` 会输出字面量 "-n"，会写坏数据。
    $local = Join-Path $env:TEMP ("e5-gpt-" + [guid]::NewGuid().ToString('N') + '.bin')
    $remote = '/data/local/tmp/.e5-gpt-' + [guid]::NewGuid().ToString('N') + '.bin'
    try {
        [IO.File]::WriteAllBytes($local, $Data)
        $push = Invoke-Adb "push `"$local`" $remote"
        if ($push -notmatch '1 file pushed') { throw "推送失败: $push" }
        $r = Invoke-Su "dd if=$remote of=/dev/block/mmcblk0 bs=512 seek=$Skip conv=notrunc 2>&1 | tail -1"
        return $r
    } finally {
        Invoke-Su "rm -f $remote" | Out-Null
        Remove-Item $local -Force -ErrorAction SilentlyContinue
    }
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

function Get-GptState {
    param([string]$AdbSerial)
    $prev = $script:AdbTarget; $script:AdbTarget = $AdbSerial
    try {
        $head = Read-Device -Skip 1 -Count 1
        $entries = Read-Device -Skip 2 -Count $EntriesSectors
        $backupLba = [long](Get-U64 $head 32)
        return [pscustomobject]@{
            Head = $head; Entries = $entries; BackupLba = $backupLba
            BackupEntries = (Read-Device -Skip ([int]($backupLba - $EntriesSectors)) -Count $EntriesSectors)
            BackupHead = (Read-Device -Skip ([int]$backupLba) -Count 1)
            LastUsable = [long](Get-U64 $head 48)
        }
    } finally { $script:AdbTarget = $prev }
}

function Get-GptPartitionOffset {
    param([string]$PartitionName, [string]$AdbSerial)
    $st = Get-GptState -AdbSerial $AdbSerial
    $e = (Get-Entries $st.Entries) | Where-Object { $_ -and $_.Name -eq $PartitionName } | Select-Object -First 1
    if (-not $e) { throw "找不到分区 $PartitionName" }
    return ($e.First * $Sector)
}

function Invoke-GptCarve {
    param([long]$UserdataSectors, [string]$Name = 'e5root', [string]$AdbSerial = '', [switch]$DryRun)
    $prev = $script:AdbTarget; $script:AdbTarget = $AdbSerial
    try {
        $st = Get-GptState -AdbSerial $AdbSerial
        $parsed = Get-Entries $st.Entries
        $ud = $parsed | Where-Object { $_ -and $_.Name -eq 'userdata' } | Select-Object -First 1
        if (-not $ud) { Die '没有 userdata 分区' }

        $existing = $parsed | Where-Object { $_ -and $_.Name -eq $Name } | Select-Object -First 1
        if ($existing) {
            $mb = [math]::Round(($existing.Last - $existing.First + 1) / 2048)
            if ($DryRun) { Ok "$Name 已存在：$($existing.First)..$($existing.Last) ($mb MiB)"; Ok "userdata: $($ud.First)..$($ud.Last)"; return }
            Die "$Name 已存在 ($mb MiB)"
        }

        $newLast = $ud.First + $UserdataSectors - 1
        if ($newLast -ge $ud.Last) { Die '新的 userdata 没有变小' }
        if ($newLast -gt $st.LastUsable) { Die 'userdata 超过最后一个可用扇区' }
        $rootFirst = $newLast + 1
        $rootSectors = $st.LastUsable - $rootFirst + 1
        if ($rootSectors -lt 2 * 1024 * 1024) { Die "空间不足：只够 $rootSectors 个扇区" }

        Ok ("userdata: {0}..{1} -> {0}..{2} ({3} sectors, {4} MiB)" -f $ud.First, $ud.Last, $newLast, $UserdataSectors, ($UserdataSectors / 2048))
        Ok ("{0}: {1}..{2} ({3} sectors, {4} MiB)" -f $Name, $rootFirst, $st.LastUsable, $rootSectors, ($rootSectors / 2048))
        if ($DryRun) { return }

        $newEntries = [byte[]]::new($st.Entries.Length)
        [Array]::Copy($st.Entries, $newEntries, $st.Entries.Length)
        Set-U64 $newEntries ($ud.Index * $EntrySize + 40) ([uint64]$newLast)

        $freeSlot = -1
        for ($i = 0; $i -lt $parsed.Count; $i++) { if ($null -eq $parsed[$i]) { $freeSlot = $i; break } }
        if ($freeSlot -lt 0) { Die 'GPT 条目表已满' }
        $entry = New-EntryBytes -Type $LinuxFsType -First $rootFirst -Last $st.LastUsable -Name $Name
        [Array]::Copy($entry, 0, $newEntries, $freeSlot * $EntrySize, $EntrySize)

        $newHead = Repair-Header -Head $st.Head -Entries $newEntries
        $newBackupHead = Repair-Header -Head $st.BackupHead -Entries $newEntries

        Write-Device -Skip 1 -Data $newHead | Out-Null
        Write-Device -Skip 2 -Data $newEntries | Out-Null
        Write-Device -Skip ([int]($st.BackupLba - $EntriesSectors)) -Data $newEntries | Out-Null
        Write-Device -Skip ([int]$st.BackupLba) -Data $newBackupHead | Out-Null
        Su 'sync' | Out-Null

        $chk = Get-GptState -AdbSerial $AdbSerial
        $ok = ($chk.Head -join ',') -eq ($newHead -join ',') -and
              ($chk.Entries -join ',') -eq ($newEntries -join ',') -and
              ($chk.BackupEntries -join ',') -eq ($newEntries -join ',') -and
              ($chk.BackupHead -join ',') -eq ($newBackupHead -join ',')
        Ok ('verify: ' + $(if ($ok) { 'OK' } else { 'MISMATCH' }))
        if (-not $ok) { Die 'GPT 写入校验失败' }
    } finally { $script:AdbTarget = $prev }
}
# =========================================================================================



if (-not $PayloadDir) {
    $base = Split-Path -Parent $PSCommandPath
    if (-not $base) { $base = (Get-Location).Path }
    $PayloadDir = Join-Path $base 'payload'
}

$Step = 0
function Info($m) { $script:Step++; Write-Host "`n[$($script:Step)] $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "    $m" -ForegroundColor Green }
function Die($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function AdbOut([string]$ArgLine) {
    $out = & cmd /c "adb $ArgLine 2>&1" | Out-String
    return $out.Trim()
}
function Su([string]$Cmd) { return AdbOut ('shell su -c "' + $Cmd + '"') }

function Expand-Gzip([string]$In, [string]$Out) {
    $src = [IO.File]::OpenRead($In)
    $dst = [IO.File]::Create($Out)
    $gz = New-Object IO.Compression.GZipStream($src, [IO.Compression.CompressionMode]::Decompress)
    $gz.CopyTo($dst)
    $gz.Dispose(); $dst.Dispose(); $src.Dispose()
}

Info '检查设备与载荷'
foreach ($f in 'e5root.ext4.gz', 'boot-linux-slotb-release.img', 'lym10k-boot-linux-magisk.zip', 'f2fs-online-arm64') {
    if (-not (Test-Path (Join-Path $PayloadDir $f))) { Die "缺少载荷 $PayloadDir\$f" }
}
# GPT 编辑由本脚本内置实现，无需 Python 或任何外部工具

$list = AdbOut 'devices'
$serials = @($list -split "`n" | Where-Object { $_ -match '\sdevice$' } | ForEach-Object { ($_ -split '\s+')[0] })
if (-not $serials) { Die '没有 adb 设备：请连接 USB、开启 USB 调试并在手机上授权' }
if (-not $AdbSerial) { $AdbSerial = $serials[0] }
Ok "设备: $AdbSerial"

if ((Su 'getprop sys.boot_completed') -ne '1') {
    Die '设备不在 Android：请先在 Linux 里执行 e5-next-boot android && reboot'
}
Ok 'Android 运行中'
if ((Su 'id -u') -ne '0') { Die 'root 不可用：请在 Magisk 里给 shell 授予超级用户权限' }
Ok 'root 可用'
Ok ("机型: " + (Su 'getprop ro.product.device'))
if ((Su 'command -v magisk || echo none') -eq 'none') { Die '未找到 magisk 命令' }

Info '在线缩容 Android /data（数据保留）'
& cmd /c "adb push `"$(Join-Path $PayloadDir 'f2fs-online-arm64')`" /data/local/tmp/f2fs-online 2>&1" 2>&1 | Out-Null
Su 'chmod 755 /data/local/tmp/f2fs-online' 2>&1 | Out-Null
$inspect = Su '/data/local/tmp/f2fs-online inspect /data /dev/block/dm-33'
Write-Host ($inspect -replace "`n", "`n    ")
$blocks = [long](($inspect -split "`n" | Where-Object { $_ -match '^blocks=' }) -replace '^blocks=', '')
if ($blocks -le 0) { Die '读不到 /data 块数' }
$targetBlocks = [long]([math]::Floor(($TargetGiB * 1GB) / 4096 / 256) * 256)
Ok "当前 $blocks 块（$([math]::Round($blocks * 4096 / 1GB, 2)) GiB）→ 目标 $targetBlocks 块（$TargetGiB GiB）"
if ($targetBlocks -ge $blocks) {
    Ok '已经不大于目标值，跳过缩容'
} elseif ($DryRun) {
    Ok '[dry-run] 会执行 shrink'
} else {
    $out = Su "/data/local/tmp/f2fs-online shrink /data /dev/block/dm-33 $blocks $targetBlocks"
    Write-Host ($out -replace "`n", "`n    ")
    if ($out -notmatch 'resize_verified=OK') { Die '缩容失败（没有 resize_verified=OK）' }
    Ok '缩容完成，Android 数据保留'
}
$userdataSectors = $targetBlocks * 8

Info '调整分区表（userdata 缩小 + 新增 e5root）'
$gptArgs = @{ UserdataSectors = $userdataSectors; Name = 'e5root'; AdbSerial = $AdbSerial }
if ($DryRun) { $gptArgs.DryRun = $true }
Invoke-GptCarve @gptArgs
if ($DryRun) { Info 'dry-run 结束，未写设备'; exit 0 }

$offsetBytes = [long](Get-GptPartitionOffset -PartitionName 'e5root' -AdbSerial $AdbSerial)
Ok "e5root 起始字节: $offsetBytes"

Info '写入 rootfs 镜像到 e5root'
$img = Join-Path $env:TEMP 'e5root.ext4'
if (-not (Test-Path $img)) {
    Info '解压 e5root.ext4.gz'
    Expand-Gzip (Join-Path $PayloadDir 'e5root.ext4.gz') $img
}
$imgSize = (Get-Item $img).Length
Ok "镜像 $([math]::Round($imgSize / 1GB, 2)) GiB"

& cmd /c "adb push `"$img`" /data/local/tmp/e5root.ext4 2>&1" 2>&1 | Out-Null
$bs = 1048576
while (($offsetBytes % $bs) -ne 0) { $bs = [long]($bs / 2) }
$seek = [long]($offsetBytes / $bs)
Ok "写入 bs=$bs seek=$seek"
$dd = Su "dd if=/data/local/tmp/e5root.ext4 of=/dev/block/mmcblk0 bs=$bs seek=$seek conv=fsync 2>&1 | tail -2"
Write-Host "    $dd"

$mb = 1048576
$srcMd5 = ((Su "dd if=/data/local/tmp/e5root.ext4 bs=$mb count=1 2>/dev/null | md5sum") -split '\s+')[0]
$dstMd5 = ((Su "dd if=/dev/block/mmcblk0 bs=$mb skip=$seek count=1 2>/dev/null | md5sum") -split '\s+')[0]
if ($srcMd5 -ne $dstMd5) { Die "首块校验失败 src=$srcMd5 dst=$dstMd5" }
Ok '首块校验通过'
Su 'rm -f /data/local/tmp/e5root.ext4' 2>&1 | Out-Null

Info '安装 Magisk 模块（Android 一键切 Linux）'
& cmd /c "adb push `"$(Join-Path $PayloadDir 'lym10k-boot-linux-magisk.zip')`" /data/local/tmp/ 2>&1" 2>&1 | Out-Null
$mout = Su 'magisk --install-module /data/local/tmp/lym10k-boot-linux-magisk.zip'
Write-Host ($mout -replace "`n", "`n    ")
if ($mout -notmatch 'Done') { Die 'Magisk 模块安装失败' }
Ok '模块已安装（下次进入 Android 后出现 Action 按钮）'

Info '写入 boot_b 并武装 slot b'
$boot = Join-Path $PayloadDir 'boot-linux-slotb-release.img'
$bootHash = (Get-FileHash $boot -Algorithm SHA256).Hash.ToLower()
& cmd /c "adb push `"$boot`" /data/local/tmp/e5-boot.img 2>&1" 2>&1 | Out-Null
if (((Su 'sha256sum /data/local/tmp/e5-boot.img') -split '\s+')[0] -ne $bootHash) { Die 'boot 镜像推送校验失败' }
Su 'dd if=/data/local/tmp/e5-boot.img of=/dev/block/by-name/boot_b bs=4M conv=fsync' 2>&1 | Out-Null
if (((Su 'sha256sum /dev/block/by-name/boot_b') -split '\s+')[0] -ne $bootHash) { Die 'boot_b 写入校验失败' }
Ok 'boot_b 写入并校验通过'

$bcFile = Join-Path $env:TEMP 'e5-bc-b.bin'
[IO.File]::WriteAllBytes($bcFile, [Convert]::FromBase64String('X2IAAEJDQUIBAgAAngAvAAAAAAAAAAAAAAAAAJv4VG0='))
& cmd /c "adb push `"$bcFile`" /data/local/tmp/e5-bc-b.bin 2>&1" 2>&1 | Out-Null
Su 'dd if=/data/local/tmp/e5-bc-b.bin of=/dev/block/by-name/misc bs=1 seek=2048 conv=notrunc' 2>&1 | Out-Null
$miscMd5 = ((Su 'dd if=/dev/block/by-name/misc bs=1 skip=2048 count=32 2>/dev/null | md5sum') -split '\s+')[0]
if ($miscMd5 -ne (Get-FileHash $bcFile -Algorithm MD5).Hash.ToLower()) { Die 'misc 写入校验失败' }
Ok 'slot b 已武装'
Su 'rm -f /data/local/tmp/e5-boot.img /data/local/tmp/e5-bc-b.bin' 2>&1 | Out-Null

Info '全部完成，重启进入 e5-linux'
& cmd /c "adb -s $AdbSerial reboot" 2>&1 | Out-Null
Ok '重启中（约 90 秒）。Linux 起不来会自动回落 Android，可用 Magisk 模块的 Action 重试'
