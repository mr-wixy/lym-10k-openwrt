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

## 已做的四项优化

### 0. WebKit 内存上限（真正的根治）

面板的 `WPENetworkProcess` 会持续泄漏，实测 **52 MB/h**（21 小时涨到 790 MB）。
但 **cog 自带 WebKit 原生的内存压力处理**（`cog --help-memory-limits`），
设了上限之后由 WebKit 自己回收，不会无限增长：

```sh
/usr/bin/cage -d -- /usr/bin/cog -P wl --bg-color=black \
	--net-mem-limit=160 --net-check-interval=30 \
	--net-conservative-threshold=0.5 --net-strict-threshold=0.75 \
	--web-mem-limit=220 --web-check-interval=30 \
	--web-conservative-threshold=0.5 --web-strict-threshold=0.75 \
	--enable-write-console-messages-to-stdout=true \
	--webprocess-failure=restart \
	http://127.0.0.1:8088/ &
```

含义：

| 参数 | 值 | 说明 |
|---|---|---|
| `--net-mem-limit` | 160 | 网络进程上限 MiB |
| `--net-check-interval` | 30 | 每 30 秒检查一次 |
| `--net-conservative-threshold` | 0.5 | 达到 50% 温和回收 |
| `--net-strict-threshold` | 0.75 | 达到 75% 强制回收 |
| `--web-mem-limit` | 220 | 渲染进程上限 MiB |

**效果**：`WPENetworkProcess` 在 74 MB 附近波动而不是单调爬升，
可用内存稳定在 **933–973 MB**。

> 顺带纠正一个误读：之前看到的 `VmData` 72 GB 是**虚拟地址空间预留**，
> 不是真实占用。真正要看的是 `VmRSS` 和 `MemAvailable`。

### 0b. glibc 分配器调优

```sh
export MALLOC_ARENA_MAX=2
export MALLOC_TRIM_THRESHOLD_=131072
```

减少内存 arena 数量，并让释放的堆尽快还给系统。

### 0c. 面板内存守护（兜底，`/etc/init.d/memguard`）

WebKit 的 **`WPENetworkProcess` 会缓慢泄漏**：实测开机 21 小时后 RSS 涨到
**790 MB**，把 1.5 GiB 内存吃到 93%，可用只剩 122 MB。
单纯重启面板就能全部回收：

| | 重启前 | 重启后 |
|---|---|---|
| 已用 | 1179 MB | 419 MB |
| 可用 | 214 MB | 977 MB |
| NetworkProcess RSS | 790 MB | 60 MB |

有了上面的内存上限后，memguard 只是兜底：

| 配置 | 默认 | 含义 |
|---|---|---|
| `e5-memguard.main.enabled` | 1 | 总开关 |
| `e5-memguard.main.min_avail_mb` | 250 | 可用内存低于此值就重启 |
| `e5-memguard.main.max_age_min` | 720 | 面板运行超过 12 小时就重启（0 关闭） |
| `e5-memguard.main.check_sec` | 60 | 检查间隔 |

> 注意：OpenWrt 没有 `getconf`。早期版本的 memguard 用它取时钟频率，
> 导致进程存活时间恒为 0、时间触发从不生效——已修正。

查看是否生效：

```sh
ps | grep e5-memguard
logread | grep e5-memguard | tail -5
```

临时关掉：

```sh
uci set e5-memguard.main.enabled=0 && uci commit e5-memguard
```

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
