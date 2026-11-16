# payload 目录说明

镜像文件**不在**本仓库里（太大），从 [Releases](../../releases) 下载。

下载到的 `LYM-10K-OpenWrt-OneShot-<日期>.zip` 解压后，结构是：

```
flash-openwrt.ps1
README.md
payload/
  e5root.ext4.gz                  OpenWrt 系统镜像（约 162 MB）
  boot-linux-slotb-release.img    启动镜像（64 MB）
  lym10k-boot-linux-magisk.zip    Magisk 模块（Android 一键切 Linux）
  f2fs-online-arm64               在线缩容工具
tools/
  gpt_carve.py                    分区表工具
```

脚本会自动在这个 `payload/` 里找文件；如果你想放到别的位置，用
`-PayloadDir <目录>` 指定。

## 校验

每个 Release 都附 `SHA256SUMS`，下载后可以校验：

```powershell
Get-FileHash .\LYM-10K-OpenWrt-OneShot-*.zip -Algorithm SHA256
```

值应和 Release 页面里的一致。
