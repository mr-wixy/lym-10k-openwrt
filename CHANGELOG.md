# 更新记录

## v1.2.2（2026-11-21）

**刷机不再需要 Python。** 只装 adb 就能刷，Windows 10/11 开箱即用。

### 变更

- 分区表（GPT）编辑从 Python 脚本移植为**纯 PowerShell 实现**，内置于
  `flash-openwrt.ps1`。工具脚本 `tools/gpt_carve.py` 已从刷机包移除。
- 不再需要安装 Python 3、Node 或任何其他运行时。

### 验证

移植后的 CRC32 与 Python `zlib` **逐字节一致**（用真机 GPT 结构做的交叉验证）：

```
entries CRC  0x6204E759   OK
主 GPT 头    0x67CA66F9   OK   字节完全一致
备份 GPT 头  0xD2A45750   OK   字节完全一致
```

标准校验值也吻合：CRC32("123456789") = `0xCBF43926`。

### 校验

```
sha256  cf862dfca4d6add2b3f66e18f1997632e20588edae6198f4141c93cd861ecc45  LYM-10K-OpenWrt-OneShot-20261117.zip
```

---

## v1.2.1（2026-11-17）

在 v1.2.0 基础上补齐内存与信息屏设置的遗留问题。

### 新增

- **息屏刷新设置**（面板 → 设置 → 显示）：

  | 设置项 | 默认 | 说明 |
  |---|---|---|
  | 息屏时继续刷新 | 开 | 关掉后息屏期间完全不请求数据 |
  | 息屏刷新间隔 | 5 秒 | 5 / 10 / 30 秒、1 / 5 分钟 |

  亮屏固定 2 秒刷新，不受影响。

- `memguard` 面板内存守护（`/etc/init.d/memguard`）：
  可用内存低于 250 MB 或面板运行超过 12 小时时自动重启面板回收内存。
  注意 OpenWrt 没有 `getconf`，早期实现用它取时钟频率导致时间触发从不生效，已修正。

### 修复

- **WebKit 内存泄漏**：面板 `WPENetworkProcess` 实测 **52 MB/h** 线性增长
  （21 小时达 790 MB，占满 1.5 GiB 内存）。改用 cog 自带的 WebKit 内存压力处理：
  `--net-mem-limit=160` / `--web-mem-limit=220`，配合阈值触发回收；
  另加 `MALLOC_ARENA_MAX=2`、`MALLOC_TRIM_THRESHOLD_`。
  修复后进程在 74 MB 附近波动，可用内存稳定在 **933–973 MB**。
- **AT 命令全部失效**：这块基带不支持 `;` 串联多条 AT
  （`AT+SPACTCARD=0;AT+CGSN` → `+CME ERROR: 65536014`），
  导致信息屏「设备信息」页字段全空。选卡与查询已拆成两次发送。
- **LuCI 首页信号空白**：`mu300dash` 走的分发器契约是
  `<适配器> <超时> <命令>`，而 `t551m-at` 要 `-t <秒> <命令>`。
  新增 `at-custom` 转接脚本，`unisoc_modem.at_command` 指向它。
- **空的 SIM2 显示成 SIM1**：固件忽略 `AT+SPACTCARD`，逐卡查询永远返回主卡数据。
  改用 ModemManager 的 `sim-slots` 判断，空槽直接标记未插卡。
- 补上 `/opt/e5/t551m-at`（`t551m-screen-details` 期望的路径）。

### 已知问题

- **VoLTE**：部分运营商/套餐 IMS 注册不上，语音通话不可用（数据和短信正常）
- **不能拔电池使用**：无电池冷启动时基带数据面不初始化，没有蜂窝网络
- **息屏关闭刷新时，短信到达不会亮屏**（响铃和震动正常）。
  **来电不受影响**：来电走独立通道，350 ms 内亮屏。
  原因：短信亮屏逻辑挂在主轮询上，来电有自己的 `calls.js` 通道。

### 校验

```
sha256  709e670b8a9b2159d3db7ee9d0d8e85fca28cc9722185b8b8f5f52792bea0d5a  LYM-10K-OpenWrt-OneShot-20261117.zip
sha256  7280ca79511249605ecf8f451e2185e97ac43724bc6181344e3ca3dfe527a211  e5root.ext4.gz
```

---

## v1.2.0（2026-11-17）

这一版把信息屏和网页的所有已知问题都修进了镜像，**重装系统后开箱即用**。

### 修复

- **AT 命令全部失效**：这块基带不支持 `;` 串联多条 AT
  （`AT+SPACTCARD=0;AT+CGSN` → `+CME ERROR: 65536014`），
  导致信息屏「设备信息」页字段全空、信号页显示"待获取运营商"。
  现在选卡与查询分两次发送。
- **LuCI 首页信号空白**：`mu300dash` 走的 AT 分发器契约是
  `<适配器> <超时> <命令>`，而 `t551m-at` 要 `-t <秒> <命令>`，
  参数不匹配导致报 `AT backend did not answer`。新增 `at-custom` 转接脚本。
- **空的 SIM2 显示成 SIM1**：固件忽略 `AT+SPACTCARD`，逐卡查询永远返回主卡数据。
  改用 ModemManager 的 `sim-slots` 判断，空槽直接标记未插卡。
- **内存泄漏**：面板 WebKit 的 `WPENetworkProcess` 21 小时涨到 790 MB
  （`VmData` 72 GB）。新增 `memguard` 自动重启面板回收。

### 新增

- `/etc/init.d/zram-swap`：512 MiB 压缩交换（内核有 ZRAM 但镜像原本没配）
- `/etc/init.d/memguard`：可用内存 < 200 MB 或面板运行 > 6 小时时自动重启面板
- WebKit 单进程模式（`WEBKIT_USE_SINGLE_WEB_PROCESS=1`），进程占用
  497 MB → 399 MB
- `/opt/e5/t551m-at`（设备信息页期望的路径）
- **SSH 公钥内置**：`/etc/dropbear/authorized_keys` 已写入，重装后免密 SSH 可用

### 变更

- 一键刷机包：`LYM-10K-OpenWrt-OneShot-20261117.zip`（197.9 MB）
- 构建方式改为「基础镜像 + 注入树」重建，不再叠加修补

### 已知问题

- **VoLTE**：部分运营商/套餐 IMS 注册不上，语音通话不可用（数据和短信正常）
- **不能拔电池使用**：无电池冷启动时基带数据面不初始化，没有蜂窝网络

### 校验

```
sha256  0bd70a15e51f536bc3f45ae17ea55732200649686355fbd22b07a86854a9a512  LYM-10K-OpenWrt-OneShot-20261117.zip
```

---

## v1.0.0（首个发布版）

**系统**

- Linux `6.18.54-lym10k-bringup1` + OpenWrt `25.12.5`
- 装在机身存储的 `e5root` 分区（4 GiB），**不需要内存卡**
- 与 Android 双系统共存，可随时切换，Android 数据保留

**刷机**

- 一条命令：`flash-openwrt.ps1`（解锁 BL + Magisk 之后）
- Android 13 的加密 `/data` 在线缩容（22 GiB → 18 GiB），数据不丢
- 分区表在电脑上计算，通过 adb 写入，主备两份 GPT 均校验
- 不需要在电脑上装 Linux

**功能**

- 面板信息屏：运营商、信号、流量、锁屏、双卡
- 蜂窝数据（4G/5G），开机自动拨号
- Wi-Fi 热点 `LYM-10K`
- 短信收发
- 来电响铃、通话音频、麦克风、静音
- 蓝牙、音频播放、充电显示
- Tailscale 内置（含访问对端子网）
- USB 网管 + LuCI + SSH

**已知问题**

- **VoLTE**：部分运营商/套餐下 IMS 注册不上，语音通话不可用；
  数据、短信、热点不受影响。需要运营商侧开通 VoLTE。
- **不能拔电池使用**：无电池（USB 供电）冷启动时基带数据面不初始化，
  表现为"显示正常但没有蜂窝网络"。属于硬件上电时序问题。

---

## 模板

```markdown
## vX.Y.Z

### 新增
-

### 修复
-

### 变更
-

### 已知问题
-

### 校验
SHA256: <zip 哈希>
```
