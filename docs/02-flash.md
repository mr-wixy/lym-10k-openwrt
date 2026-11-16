# 一键刷机详解

假设你已经完成 [刷机前必读](01-preparation.md)：解锁 bootloader、装好 Magisk、
电脑有 adb 和 Python 3。

---

## 1. 下载刷机包

到本仓库的 [Releases](../../releases) 页面，下载最新的：

```
LYM-10K-OpenWrt-OneShot-<日期>.zip    约 190 MB
```

解压到**纯英文路径**（例如 `D:\LYM-10K`）。里面有：

```
flash-openwrt.ps1         一键脚本
README.md                 包内说明
payload\                  镜像与工具（不要动）
  e5root.ext4.gz            OpenWrt 系统镜像
  boot-linux-slotb-release.img  启动镜像
  lym10k-boot-linux-magisk.zip  Magisk 模块（Android 一键切 Linux）
  f2fs-online-arm64        缩容工具
tools\gpt_carve.py         分区表工具
```

---

## 2. 先看一眼计划（推荐）

手机开机、进 Android、插上 USB，在解压目录里执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1 -DryRun
```

正常输出类似：

```
[1] 检查设备与载荷
    设备: XXXXXXXXXXXXXXX
    Android 运行中
    root 可用
    机型: RY5G

[2] 在线缩容 Android /data（数据保留）
blocks=5667328
    block_size=4096
    当前 5667328 块（21.61 GiB）→ 目标 4718592 块（18 GiB）
    [dry-run] 会执行 shrink

[3] 调整分区表（userdata 缩小 + 新增 e5root）
userdata: 15278080..52228095 -> 15278080..52228031 (36950016 sectors, 18041 MiB)
e5root: 52228032..60616703 (8388672 sectors, 4096 MiB)

[4] dry-run 结束，未写设备
```

看到 `dry-run 结束，未写设备` 就说明环境没问题。

---

## 3. 正式刷入

```powershell
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1
```

它会依次做（每步都有彩色输出）：

| 步骤 | 做什么 | 耗时 |
|---|---|---|
| 1 | 检查设备 / root / 载荷 | 几秒 |
| 2 | 把 Android 的 `/data` 从约 22 GiB 在线缩到 18 GiB（**数据保留**） | 约 1 分钟 |
| 3 | 改分区表：`userdata` 缩小，后面新建 `e5root`（4 GiB） | 几秒 |
| 4 | 把 OpenWrt 镜像写进 `e5root`，校验首块 | 2–4 分钟 |
| 5 | 安装 Magisk 模块（Android 一键切 Linux） | 几秒 |
| 6 | 写启动镜像 `boot_b`、设置下次从 Linux 启动、重启 | 几秒 + 重启 90 秒 |

**全程 5–10 分钟**。中途不要拔线、不要断电。

最后看到：

```
[7] 全部完成，重启进入 e5-linux
    重启中（约 90 秒）...
```

手机重启后，先黑屏几秒 → 出现开机画面 → 约 90 秒后屏幕显示信息屏（运营商/信号/时间）。

---

## 4. 刷完怎么用

见 [第一次启动](03-first-boot.md)。

---

## 5. 参数说明

| 参数 | 作用 |
|---|---|
| `-DryRun` | 只检查、打印计划，不写手机 |
| `-TargetGiB 16` | 缩容后 Android `/data` 的大小（默认 18，越小给 Linux 留的空间越多） |
| `-AdbSerial <序列号>` | 电脑接了多台设备时指定 |

例：

```powershell
# 给 Linux 留 6 GiB：把 /data 缩到 16 GiB
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1 -TargetGiB 16
```

---

## 6. 刷机做了什么（想了解原理的人看）

LYM-10K 的 Android 13 把 `/data` 做了 **metadata 加密**（dm-default-key），
所以不能像普通手机那样"离线缩容"。脚本的做法是：

1. 用 e5-linux 项目自带的 `f2fs-online` 工具，通过**已解密的 dm 设备**在线缩容；
2. 在电脑上计算新的分区表（GPT），通过 adb 只读写那 17 KiB 的区域；
3. 把系统镜像直接写到整盘的 `e5root` 偏移处（绕开"分区表改动后内核不重新读取"的问题）；
4. 写 `boot_b` 启动镜像，并在 `misc` 里把 b 槽位标记为"下次启动"。

Android 的系统分区和你的数据都没动，只是把 `/data` 变小了一点。
