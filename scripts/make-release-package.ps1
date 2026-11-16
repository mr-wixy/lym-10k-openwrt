param(
    [Parameter(Mandatory = $true)][string]$E5rootGz,
    [Parameter(Mandatory = $true)][string]$BootImage,
    [Parameter(Mandatory = $true)][string]$MagiskZip,
    [Parameter(Mandatory = $true)][string]$F2fsTool,
    [string]$Version = (Get-Date -Format 'yyyyMMdd')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'release'
$stage = Join-Path $out "LYM-10K-OpenWrt-OneShot-$Version"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$stage\payload", "$stage\tools" | Out-Null

Copy-Item (Join-Path $root 'scripts\flash-openwrt.ps1') $stage -Force
Copy-Item (Join-Path $root 'README.md') (Join-Path $stage 'README.md') -Force
Copy-Item (Join-Path $root 'scripts\gpt_carve.py') (Join-Path $stage 'tools') -Force

Copy-Item $E5rootGz (Join-Path $stage 'payload\e5root.ext4.gz') -Force
Copy-Item $BootImage (Join-Path $stage 'payload\boot-linux-slotb-release.img') -Force
Copy-Item $MagiskZip (Join-Path $stage 'payload\lym10k-boot-linux-magisk.zip') -Force
Copy-Item $F2fsTool (Join-Path $stage 'payload\f2fs-online-arm64') -Force

$zip = Join-Path $out "LYM-10K-OpenWrt-OneShot-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Fastest

$lines = Get-ChildItem $out -File -Filter '*.zip' | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)"
}
$lines | Set-Content (Join-Path $out 'SHA256SUMS') -Encoding ASCII

Get-Item $zip | Select-Object Name, @{n='MB'; e={[math]::Round($_.Length / 1MB, 1)}}
Get-Content (Join-Path $out 'SHA256SUMS')
Write-Host "`n上传：gh release create v$Version `"$zip`" `"$(Join-Path $out 'SHA256SUMS')`" --title `"LYM-10K OpenWrt v$Version`""
