# 从构建产物生成发布包（维护者用）

把构建机上的几个文件打成 `LYM-10K-OpenWrt-OneShot-<日期>.zip`，并生成 `SHA256SUMS`。

    # Windows
    powershell -ExecutionPolicy Bypass -File .\scripts\make-release-package.ps1 `
        -E5rootGz  D:\build\e5root.ext4.gz `
        -BootImage D:\build\boot-linux-slotb-release.img `
        -MagiskZip D:\build\lym10k-boot-linux-magisk.zip `
        -F2fsTool  D:\build\f2fs-online-arm64

    # Linux / macOS
    ./scripts/make-release-package.sh /path/to/artifacts

产物在 `release/` 下，直接上传到 GitHub Releases。详见 [RELEASING.md](../RELEASING.md)。
