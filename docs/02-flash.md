# 一键刷机详解

假设你已经完成 [刷机前必读](01-preparation.md)：解锁 bootloader、装好 Magisk。
电脑只需要 **adb**，不需要 Python 或任何其他运行时。

> 本文的步骤与截图输出来自 **2026-11-21 的真机实测**（LYM-10K / RY5G）。

---

## 1. 下载并解压

到本仓库的 [Releases](../../releases) 页面，下载最新的一键包：

```
LYM-10K-OpenWrt-OneShot-<日期>.zip    约 198 MB
```

解压到**纯英文路径**（例如 `D:\LYM-10K`，不要放在中文或带空格的目录）。内容：

```
flash-openwrt.ps1          一键刷机脚本
一键刷机.cmd                双击运行（自动提权、出错不闪退）
check-gpt.ps1              分区表自检（出问题时才用）
README.md                  包内说明
payload\                   镜像与工具，不要改动
  e5root.ext4.gz             OpenWrt 系统镜像（2 GiB，压缩后 172 MB）
  boot-linux-slotb-release.img   启动镜像
  lym10k-boot-linux-magisk.zip   Magisk 模块（Android 一键切 Linux）
  f2fs-online-arm64          在线缩容工具
```

---

## 2. 准备手机

1. 手机**开机进入 Android**（不是 Linux）；
2. 用数据线连电脑；
3. 开发者选项里确认 **USB 调试** 已开，弹窗时点**允许**；
4. 确认 adb 认到设备：

   ```powershell
   adb devices
   # 应输出： S3503HRF...  device
   ```

5. **备份数据**（建议）：

   ```powershell
   adb exec-out su -c "tar -cf - /data" > data-backup.tar
   ```

---

## 3. 先看计划（推荐）

```powershell
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1 -DryRun
```

`-DryRun` 会**真实连接手机、读取分区表和 /data 大小**，但**不写入任何东西**
（只在手机临时目录放一个 555 KB 的缩容工具）。

全新机器的正常输出：

```
[1] 检查设备与载荷
    设备: S3503HRF240613001520
    Android 运行中
    root 可用
    机型: RY5G

[2] 在线缩容 Android /data（数据保留）
blocks=5667328
    block_size=4096
    当前 5667328 块（21.62 GiB）→ 目标 4718592 块（18 GiB）
    [dry-run] 会执行 shrink

[3] 调整分区表（userdata 缩小 + 新增 e5root）
    userdata: 15278080..60616703 -> 15278080..53026815 (37748736 sectors, 18432 MiB)
    e5root: 53026816..60616703 (7589888 sectors, 3706 MiB)

[4] dry-run 结束，未写设备
```

**重点核对**：`e5root` 的大小（上面是 3706 MiB）。如果显示「已存在」，说明这台机器
已经装过 Linux，不要再刷。

---

## 4. 正式刷入

```powershell
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1
```

或者**直接双击** `一键刷机.cmd`（会请求管理员权限，结束前不关窗口）。

实测输出（真机，2026-11-21）：

```
[1] 检查设备与载荷 ................ 设备 / Android / root / Magisk 全部通过

[2] 在线缩容 Android /data（数据保留）
    ioctl_begin expected=5667328 target=4718592
    resize_verified=OK
    blocks=4718592
    缩容完成，Android 数据保留

[3] 调整分区表（userdata 缩小 + 新增 e5root）
    userdata: 15278080..60616703 -> 15278080..53026815 (18432 MiB)
    e5root: 53026816..60616703 (3706 MiB)
    verify: OK
    e5root 起始字节: 27149729792

[4] 写入 rootfs 镜像到 e5root
[5] 解压 e5root.ext4.gz
    镜像 2 GiB
    写入 bs=1048576 seek=25892
    2048+0 records out
    2147483648 bytes (2.0 G) copied, 46.5 s, 44 MB/s
    首块校验通过

[6] 安装 Magisk 模块
    - Extracting module files
    - Done
    模块已安装

[7] 写入 boot_b 并武装 slot b
    boot_b 写入并校验通过
    slot b 已武装

[8] 全部完成，重启进入 e5-linux
    重启中（约 90 秒）
```

各步耗时参考：

| 步骤 | 耗时 |
|---|---|
| 1 检查 | 几秒 |
| 2 缩容 | 约 1 分钟 |
| 3 改分区表 | 几秒 |
| 4-5 写镜像 | **约 47 秒**（USB 约 44 MB/s） |
| 6 Magisk 模块 | 几秒 |
| 7 boot_b + misc | 几秒 |
| **合计** | **约 3 分钟 + 重启 90 秒** |

**全程不要拔线、不要断电。**

---

## 5. 刷完

手机自动重启 → 黑屏几秒 → 开机画面 → 约 90 秒后屏幕显示信息屏
（运营商、信号、时间、电量）。

接着看 [第一次启动](03-first-boot.md) 连网、进网页、改密码。

---

## 6. 参数说明

| 参数 | 作用 |
|---|---|
| `-DryRun` | 只读检查并打印计划，不写手机 |
| `-TargetGiB 16` | 缩容后 Android `/data` 的大小（默认 18）。**越小，留给 Linux 的空间越大** |
| `-AdbSerial <序列号>` | 电脑接了多台设备时指定 |

例：给 Linux 留更多空间（`/data` 缩到 16 GiB，`e5root` 约 5.7 GiB）：

```powershell
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1 -TargetGiB 16
```

> 注意：`-TargetGiB` **只在第一次刷机时有效**。刷过一次后 `/data` 已经是缩小后的
> 大小，再改这个参数不会生效（脚本会显示「跳过缩容」）。

---

## 7. 它到底做了什么

LYM-10K 的 Android 13 对 `/data` 做了 **metadata 加密**（dm-default-key），
所以不能像普通手机那样"离线缩容"。脚本的做法是：

1. 用 e5-linux 项目自带的 `f2fs-online` 工具，通过**已解密的 dm 设备**在线缩容；
2. 在电脑上计算新分区表（GPT），只读写那 17 KiB 的区域，
   主份和备份份都重写并重算 CRC32，写完立即读回校验；
3. 把系统镜像直接写到整盘的 `e5root` 偏移处（绕开"分区表改动后内核不缓存"的问题），
   并校验首个 1 MiB 与源镜像一致；
4. 写 `boot_b` 启动镜像（校验 sha256），并在 `misc` 里把 b 槽位标记为"下次启动"。

Android 的系统分区（`super`）和你的数据都没动，只是把 `/data` 缩小了一点。