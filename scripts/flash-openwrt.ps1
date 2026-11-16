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
$gptTool = Join-Path $base 'tools\gpt_carve.py'
if (-not (Test-Path $gptTool)) { Die "缺少 GPT 工具 $gptTool" }
$py = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $py) { Die '需要 Python 3（编辑 GPT 用）' }

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
$carve = @($gptTool, '--userdata-sectors', $userdataSectors)
if ($AdbSerial) { $carve += @('--serial', $AdbSerial) }
if ($DryRun) { $carve += '--dry-run' }
& $py.Source @carve
if ($LASTEXITCODE -ne 0) { Die 'GPT 操作失败' }
if ($DryRun) { Info 'dry-run 结束，未写设备'; exit 0 }

$offsetBytes = [long]((& $py.Source @($gptTool, '--print-offset', 'e5root', '--serial', $AdbSerial) | Out-String).Trim())
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
