# 从源码构建（想自己编译的人看）

本仓库只发布成品。编译方法、内核配置、ModemManager 补丁等**完整构建资料**在：

👉 **https://github.com/<你的账号>/LYM-10K-e5-linux**

那个仓库包含：

- 内核编译脚本（试启动 / 发布两种 cmdline）
- 启动镜像打包（`boot_b`、`misc` 槽位控制）
- ModemManager 三个 LYM-10K 补丁
- OpenWrt 根文件系统的组装、首启脚本、面板服务
- 每个坑的现象/根因/修法（`docs/build-log.md`）

## 本仓库镜像的版本

| 项目 | 值 |
|---|---|
| 内核 | `6.18.54-lym10k-bringup1` |
| OpenWrt | `25.12.5 r33051-f5dae5ece4` |
| ModemManager | `1.24.0-r951` + 本项目补丁 |
| 根文件系统 | ext4，2 GiB（分区 4 GiB，`resize2fs` 扩到 4 GiB） |
| 启动镜像 | 64 MiB，写 `boot_b` |

## 自己改镜像后怎么发布

1. 按上游仓库说明构建出 `e5-openwrt-lym10k.ext4`；
2. 用 `scripts/prep-e5root-image.sh` 加上 `part-root` 标记；
3. `gzip -9` 压缩；
4. 按 [RELEASING.md](../RELEASING.md) 打包发布。

> 注意：如果改了内核，`boot-linux-slotb-release.img` 必须一起重新生成，
> 否则启动镜像里的内核模块与系统不匹配。
