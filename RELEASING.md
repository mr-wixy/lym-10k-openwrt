# 发布新版本（维护者用）

本仓库只放**文档和脚本**；镜像文件（约 190 MB）放在 GitHub Releases，
因为 GitHub 单文件限制 100 MB、附件仓库会让 clone 变得很慢。

## 1. 准备发布包

在构建机上（见 `docs/BUILD.md`）：

```bash
# 1) 准备带 part-root 标记的系统镜像
scripts/prep-e5root-image.sh          # 输出 out/firmware/e5root.ext4
gzip -9 -c out/firmware/e5root.ext4 > e5root.ext4.gz

# 2) 组装包目录
mkdir -p release/payload release/tools
cp flash-openwrt.ps1  release/
cp README-oneshot.md  release/README.md
cp e5root.ext4.gz boot-linux-slotb-release.img \
   lym10k-boot-linux-magisk.zip f2fs-online-arm64  release/payload/
cp gpt_carve.py  release/tools/

# 3) 打包
cd release && zip -r ../LYM-10K-OpenWrt-OneShot-$(date +%Y%m%d).zip . && cd ..
```

## 2. 创建 Release

```bash
TAG=v1.0.0
gh release create "$TAG" \
  --title "LYM-10K OpenWrt $TAG" \
  --notes-file RELEASE_NOTES.md \
  LYM-10K-OpenWrt-OneShot-*.zip
```

Release 里建议同时上传：

| 文件 | 说明 |
|---|---|
| `LYM-10K-OpenWrt-OneShot-<日期>.zip` | 一键刷机包（主推） |
| `boot-linux-slotb-release.img` | 只想要启动镜像的人 |
| `e5root.ext4.gz` | 只想要系统镜像的人 |
| `SHA256SUMS` | 校验和 |

## 3. 版本号与变更说明

`RELEASE_NOTES.md` 建议包含：

```markdown
## 新增
- ...

## 修复
- 通话静音在通话建立时被覆盖

## 已知问题
- VoLTE 需要运营商开通

## 校验
SHA256: <zip 的哈希>
```

## 4. 版本兼容

| 项目 | 值 |
|---|---|
| 内核 | 6.18.54-lym10k-bringup1 |
| OpenWrt | 25.12.5 |
| ModemManager | 1.24.0-r951 + 本项目补丁 |
| 适用机型 | LYM-10K（RY5G / UMS9621） |

换内核或换 OpenWrt 版本时请在 Release 说明里单独标注。
