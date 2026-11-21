# 确认设备当前 GPT 状态（只读，不做任何修改）
# 用法：把本文件内容复制到另一台电脑的 PowerShell 里执行
Write-Host '=== 当前 GPT 状态 ===' -ForegroundColor Cyan

$b64 = (& cmd /c "adb shell su -c ""dd if=/dev/block/mmcblk0 bs=512 skip=1 count=1 2>/dev/null | base64""" | Out-String) -replace '\s',''
if (-not $b64) { Write-Host '读取失败' -ForegroundColor Red; return }
$head = [Convert]::FromBase64String($b64)

$sig = [Text.Encoding]::ASCII.GetString($head[0..7])
Write-Host "签名: '$sig'  (应为 'EFI PART')"

$backupLba = [BitConverter]::ToUInt64($head, 32)
$firstUsable = [BitConverter]::ToUInt64($head, 40)
$lastUsable = [BitConverter]::ToUInt64($head, 48)
Write-Host "backup_lba  : $backupLba  (应约为 60620799)"
Write-Host "first_usable: $firstUsable"
Write-Host "last_usable : $lastUsable  (应为 60616703)"

$crcStored = [BitConverter]::ToUInt32($head, 16)
Write-Host ("header CRC   : 0x{0:X8}" -f $crcStored)

# 校验 header CRC 是否自洽
function Get-Crc32([byte[]]$d) {
    $t = New-Object 'uint32[]' 256
    $POLY = [uint64]3988292384
    for ($n=0; $n -lt 256; $n++) {
        [uint64]$c = [uint64]$n
        for ($k=0; $k -lt 8; $k++) { if ($c -band 1) { $c = [uint64]($POLY -bxor ($c -shr 1)) } else { $c = [uint64]($c -shr 1) } }
        $t[$n] = [uint32]($c -band 4294967295)
    }
    [uint64]$crc = 4294967295
    foreach ($x in $d) { $crc = [uint64]($t[[int](($crc -bxor $x) -band 0xFF)] -bxor ($crc -shr 8)); $crc = $crc -band 4294967295 }
    return [uint32]($crc -bxor 4294967295)
}
$h = [byte[]]::new($head.Length); [Array]::Copy($head,$h,$head.Length)
$h[16]=0; $h[17]=0; $h[18]=0; $h[19]=0
$calc = Get-Crc32 $h[0..91]
Write-Host ("calc CRC     : 0x{0:X8}  {1}" -f $calc, $(if ($calc -eq $crcStored) {'OK 头部完好'} else {'MISMATCH 头部已损坏'}))

Write-Host ''
Write-Host '=== 分区表条目 ===' -ForegroundColor Cyan
$e64 = (& cmd /c "adb shell su -c ""dd if=/dev/block/mmcblk0 bs=512 skip=2 count=32 2>/dev/null | base64""" | Out-String) -replace '\s',''
if ($e64) {
    $ent = [Convert]::FromBase64String($e64)
    for ($i=0; $i -lt 128; $i++) {
        $o = $i*128
        $allZero = $true
        for ($j=0; $j -lt 16; $j++) { if ($ent[$o+$j] -ne 0) { $allZero=$false; break } }
        if ($allZero) { continue }
        $first = [BitConverter]::ToUInt64($ent, $o+32)
        $last = [BitConverter]::ToUInt64($ent, $o+40)
        $nm = ([Text.Encoding]::Unicode.GetString($ent, $o+56, 72)).TrimEnd([char]0)
        Write-Host ("  [{0,2}] {1,-12} {2}..{3}" -f $i, $nm, $first, $last)
    }
}