# LYM-10K 刷 OpenWrt（小白版）

把**岭燕 LYM-10K**（安卓机型 `RY5G`）刷成 **Linux + OpenWrt**，和原来的 Android
**双系统共存**，开机时随时切换，不需要内存卡。

> 本仓库只放**说明、一键脚本和排障手册**。
> 镜像文件较大，放在 [Releases](../../releases) 里下载。

---

## 我需要准备什么

| 需要 | 说明 |
|---|---|
| LYM-10K 手机 | 系统正常、能开机 |
| Windows 电脑 | 用来刷机（Win10/11 都行） |
| USB 数据线 | 能传数据的那种，不是只能充电的 |
| 一颗能折腾的心 | 刷机会改动系统分区，请先看完 [刷机前必读](docs/01-preparation.md) |

**不需要**：内存卡、Linux 电脑、拆机、焊接。

---

## 五分钟上手

### 第 1 步：解锁 + Root（只需做一次）

按照 [docs/01-preparation.md](docs/01-preparation.md) 操作：

1. 解锁 bootloader（会清空手机数据）
2. 刷入 Magisk 获得 root
3. 电脑装好 `adb` 和 `Python 3`

### 第 2 步：下载并解压刷机包

到 [Releases](../../releases) 下载最新的
`LYM-10K-OpenWrt-OneShot-<日期>.zip`，解压到一个**纯英文路径**的文件夹，
例如 `D:\LYM-10K`。

### 第 3 步：一键刷入

手机开机进入 **Android** 系统，插上 USB 线，在解压后的文件夹里执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1
```

脚本会自己检查设备、缩容、分区、写入镜像，全程 5–10 分钟。
看到 `重启中` 就等着，大约 90 秒后进入 OpenWrt。

> 想先看看它要做什么、不写手机？加上 `-DryRun`：
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\flash-openwrt.ps1 -DryRun
> ```

### 第 4 步：连上它

| 方式 | 地址 |
|---|---|
| 浏览器打开 | <http://192.168.9.1/> |
| SSH | `ssh root@192.168.9.1` |
| Wi-Fi 热点 | 名称 `LYM-10K`，密码 `12345678` |

电脑网卡需要设成 `192.168.9.2 / 255.255.255.0`（如果打不开网页，见
[docs/03-first-boot.md](docs/03-first-boot.md)）。

### 第 5 步：在 Android 和 Linux 之间切换

| 想去的系统 | 怎么做 |
|---|---|
| **Android → Linux** | 打开 Magisk → 模块 → `LYM-10K Boot Linux` → 点 **Action** |
| **Linux → Android** | 网页/SSH 里执行 `e5-next-boot android && reboot` |

---

## 装好之后能用什么

| 功能 | 状态 |
|---|---|
| 触屏、320×480 面板、信息屏 UI | ✅ |
| Wi-Fi 热点、蜂窝上网（4G/5G） | ✅ |
| 短信收发 | ✅ |
| 来电响铃、通话音频、麦克风 | ✅ |
| 蓝牙、音频播放、充电显示 | ✅ |
| Tailscale（含访问对端子网） | ✅ 已内置 |
| **VoLTE 语音通话** | ⚠️ 部分运营商不可用，见 [排障](docs/05-troubleshooting.md#volte-打电话没声音) |
| Android 原系统 | ✅ 保留，可随时切回 |

---

## 遇到问题

先看 **[docs/05-troubleshooting.md](docs/05-troubleshooting.md)**，这里按"现象"索引了
常见问题（刷机卡住、网页打不开、没信号、没声音……），都写了原因和解决办法。

其他文档：

- [刷机前必读](docs/01-preparation.md) —— 解锁、Root、电脑环境
- [一键刷机详解](docs/02-flash.md) —— 每一步在干什么、正常输出长什么样
- [第一次启动](docs/03-first-boot.md) —— 联网、进网页、改密码
- [双系统切换](docs/04-switch.md) —— 两个方向的切换方法
- [常见问题](docs/05-troubleshooting.md) —— 出问题先看这里
- [FAQ](docs/06-faq.md) —— 会不会丢数据、能不能卸载、保修怎么办
- [内存占用](docs/07-memory.md) —— 1.5 GiB 都花在哪、怎么优化

---

## 安全与恢复

- 刷机**保留 Android 系统和你的数据**（只把 `/data` 从约 22 GiB 缩到 18 GiB）。
- Linux 装在独立分区 `e5root` 里，Android 仍在原分区，**互不影响**。
- 万一 Linux 起不来，手机会自动回到 Android；具体恢复步骤见
  [排障手册](docs/05-troubleshooting.md#linux-起不来)。
- 刷机有风险，重要资料请先备份。

---

## 致谢

内核、设备适配和大部分系统组件来自开源项目
[sprd-linux-devs/e5-linux](https://github.com/sprd-linux-devs/e5-linux) 与
[Enceka/linux-lts-e5](https://github.com/Enceka/linux-lts-e5)；
本仓库提供 LYM-10K 上的一键安装封装、文档与实测排障记录。

许可：文档与脚本 MIT；镜像内的上游组件遵循其各自许可。
