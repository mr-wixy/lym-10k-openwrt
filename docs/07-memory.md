# 内存占用分析（1.5 GiB 机型）

`free` 里看到的 "free 600 多 M" 是**完全没被使用的内存**；Linux 会把不用的内存拿去做缓存，
真正可用看 `available` 列。

这台机器典型状态（优化后）：

```
              total        used        free      shared  buff/cache   available
Mem:        1537296      414180      765808       54488      357308     1010152
Swap:        524284           0      524284
```

即：总计 1.5 GiB，进程实际用掉约 **404 MB**，缓存 349 MB，**可用约 987 MB**。

## 谁在占内存

| 进程 | RSS | 说明 |
|---|---|---|
| `WPEWebProcess` | ~164 MB | 面板信息屏的 WebKit 渲染进程（最大头） |
| `WPENetworkProcess` | ~68 MB | WebKit 的网络进程 |
| `cog` | ~65 MB | 信息屏浏览器外壳 |
| `tailscaled` | ~56 MB | Tailscale（Go 程序，常驻） |
| `cage` | ~44 MB | Wayland 合成器 |
| `cp_diskserver` | ~32 MB | 原厂 CP 磁盘服务（基带必需） |
| `e5-hfp` | ~22 MB | 蓝牙耳机通话（HFP）网关 |
| `e5-mm-state` | ~21 MB | 模组状态采样 |
| `e5-call-audio-watch` | ~20 MB | 通话音频看护 |
| `e5-sms-receive` | ~17 MB | 短信接收 |
| `unisoc-ra-renew` | ~12 MB | IPv6 RA |
| `e5-network-recovery` | ~11 MB | 网络自愈 |
| `t551m-sim-status` | ~11 MB | 逐卡信号采样 |
| `ModemManager` | ~9 MB | 拨号/模组管理 |

WebKit 四件套合计约 **340 MB**，是这块 1.5 GiB 内存的主要压力来源；
其余是若干 Python 看护进程（每个解释器 10–20 MB）。

## 已经做的两项优化

### 1. WebKit 单进程模式

在 `/usr/libexec/e5-infoscreen/session` 里加：

```sh
export WEBKIT_USE_SINGLE_WEB_PROCESS=1
```

实测 `used` 从 497 MB 降到 399 MB（网络进程 RSS 122 MB → 60 MB）。

### 2. 启用 512 MiB zram 交换

内核有 ZRAM 但镜像没配交换。新增 `/etc/init.d/zram-swap`：

```sh
START=10
start() {
    modprobe zram 2>/dev/null || true
    [ -e /dev/zram0 ] || return 0
    grep -q '^/dev/zram0' /proc/swaps && return 0
    swapoff /dev/zram0 2>/dev/null || true
    echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    echo 536870912 > /sys/block/zram0/disksize || return 0
    mkswap /dev/zram0 >/dev/null 2>&1 || return 0
    swapon /dev/zram0 2>/dev/null || true
}
```

`/etc/init.d/zram-swap enable` 后开机自动生效。压缩算法默认 `lz4`。

## 还想再省内存

| 做法 | 省多少 | 代价 |
|---|---|---|
| `/etc/init.d/tailscale stop`（不用 Tailscale 时） | ~56 MB | 内网穿透不可用 |
| `/etc/init.d/e5-hfp stop`（不用蓝牙耳机打电话） | ~22 MB | 蓝牙通话无音频 |
| 加大 zram 到 1 GiB（`ZRAM_SWAP_SIZE`） | 不算"省"，但能扛更多冷页 | 压缩/解压略耗 CPU |
| 不要拔电池使用 | —— | 无电池时基带数据面起不来（见 FAQ） |

不建议为了省内存去杀掉 `cp_diskserver` / `modem_control`，那是基带运行必需；
也不建议停 `e5-mm-state`、`e5-sms-receive`，会丢功能。
