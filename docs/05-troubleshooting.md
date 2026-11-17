# 常见问题排查

按现象查。每条都写了「原因」和「怎么修」，命令可以直接复制。

---

## 刷机阶段

### adb 看不到设备

**现象**：脚本提示 `没有 adb 设备`，或 `adb devices` 列表为空。

**原因**：USB 调试没开、没授权、线只供电、或驱动没装。

**处理**：

1. 手机上「开发者选项 → USB 调试」打开；
2. 拔插数据线，手机上弹出「允许 USB 调试」时点**允许**（勾选"始终允许"）；
3. 换一根**能传数据**的线（很多线只能充电）；
4. Windows 设备管理器里看有没有"其他设备/未知设备"，有就装 adb 驱动；
5. `adb kill-server && adb devices` 重启 adb 服务。

---

### root 不可用（Permission denied）

**现象**：脚本提示 `root 不可用`，或 `adb shell su -c id` 报 Permission denied。

**原因**：Magisk 没给 shell 超级用户权限。

**处理**：

1. 打开 Magisk → 设置 → 超级用户，确认没有把 shell 设为"拒绝"；
2. 执行一次 `adb shell su -c id`，手机上会弹授权框，点**允许**；
3. 还是不行就 Magisk → 设置 → 超级用户 → 把 shell 的权限改成"允许"。

---

### 缩容失败 / Magic Mismatch

**现象**：脚本在「在线缩容」这一步失败，报 `Magic Mismatch` 或 `resize_verified` 不对。

**原因**：`/data` 是 Android 13 的 metadata 加密分区（正常现象），
必须通过已解密的 dm 设备操作；如果设备的 dm 设备名不是 `/dev/block/dm-33`，
脚本就会走错。

**处理**：

```powershell
# 看看 /data 实际挂在哪个 dm 设备上
adb shell su -c "mount | grep ' /data '"
```

把输出里 `/dev/block/dm-XX` 的数字记下来，然后手动执行一次（把 33 换成你的数字）：

```powershell
adb shell su -c "/data/local/tmp/f2fs-online inspect /data /dev/block/dm-33"
```

如果 inspect 能正常输出 `blocks=...`，说明设备名对了；否则请到 Issues 反馈。

> 缩容前建议先备份：`adb exec-out su -c "tar -cf - /data" > data-backup.tar`

---

### 分区表写入失败 / 校验不通过

**现象**：第 3 步报 `GPT 操作失败` 或 `verify: MISMATCH`。

**原因**：极少数情况下 adb 传输被中断，导致 GPT 写入不完整。

**处理**：**不要重启**，直接重跑一次脚本（GPT 写入是幂等的，会重新写一遍）。
如果反复失败，请**先插一张 TF 卡**（带系统）从卡启动，再用
[高级排障](#高级用-tf-卡救砖) 里的方法修复。

---

## 启动阶段

### 刷完重启后一直进 Android

**原因**：Linux 启动失败了 2 次，bootloader 自动回落到 Android（这是保护机制）。

**处理**：

1. 确认 `boot_b` 写对了：重跑一次刷机脚本的第 6 步（或整个脚本，前面的步骤会跳过）；
2. 检查 `misc` 是否被改回去：在 Android 里执行
   ```powershell
   adb shell su -c "dd if=/dev/block/by-name/misc bs=1 skip=2048 count=32 2>/dev/null | xxd"
   ```
   正常应以 `5f62 0000 4243 4142` 开头；
3. 还是不行，见下面的「Linux 起不来」。

---

### Linux 起不来（卡在开机画面 / 黑屏）

**处理顺序**（从简单到复杂）：

1. **等满 3 分钟**：第一次启动要初始化配置，比较慢；
2. **插串口看日志**（最有效）：USB-TTL 接板上 TX/RX/GND，波特率 115200，
   能看到内核启动到哪一步挂了；
3. **回落 Android**：长按电源强制关机再开机，bootloader 会回落；
4. **从 TF 卡救**：见 [高级：用 TF 卡救砖](#高级用-tf-卡救砖)。

---

### 高级：用 TF 卡救砖

如果 Linux 完全起不来、Android 也起不来（比如分区表被写坏），
可以用一张 TF 卡启动临时系统来修：

1. 找一张 ≥ 4 GB 的 TF 卡；
2. 用另一个正常 Linux 电脑把 `payload/e5root.ext4.gz` 解压后写入卡
   （`dd if=e5root.ext4 of=/dev/sdX bs=4M`）；
3. 挂载卡，创建标记文件：
   ```sh
   sudo mkdir -p /mnt/card/etc/e5
   sudo touch /mnt/card/etc/e5/sd-root
   sudo umount /mnt/card
   ```
4. 把卡插进手机，开机 → 会从卡启动；
5. 在卡系统里修好 `e5root` 分区或分区表，再拔卡重启。

---

## 网络

### 网页打不开（192.168.9.1）

**原因**：电脑网卡没设 IP，或驱动没装，或 USB 网卡被禁用。

**处理**：

1. 电脑「网络连接」里找到新出现的网卡（`UsbNcm Host Device` 之类），
   设成 `192.168.9.2 / 255.255.255.0`；
2. 如果它是**禁用**状态，右键启用（需要管理员权限）；
3. `ping 192.168.9.1` 能通但网页打不开 → 换个浏览器或用 `curl http://192.168.9.1/` 试；
4. 优先用 Wi-Fi 连：手机热点 `LYM-10K` / `12345678`，连上后同样访问 `192.168.9.1`。

---

### 蜂窝没有网络

**现象**：信息屏有信号，但上不了网；`ubus call network.interface.wan status` 里
`up: false`。

**逐步检查**（SSH 里执行）：

```sh
# 1. 模组认到了吗
mmcli -L

# 2. 注册上了吗（要 state: registered）
mmcli -m any | grep -E 'state|access tech|signal quality'

# 3. 数据口有 IP 吗（正常会有一个 100.x 的地址）
ip -4 addr show sipa_eth0

# 4. 接口状态
ubus call network.interface.wan status | grep -E '"up"|"code"'
```

常见错误码与含义：

| 错误码 | 含义 | 处理 |
|---|---|---|
| `NO_DEVICE` | 没找到模组设备 | `mmcli -L` 看是否为空；为空则重启模组或重启手机 |
| `MM_CONNECT_FAILED` | 拨号失败 | 看 `logread \| grep -i bearer`，常见是 PDP 激活失败 |
| `ROAMING_POLICY_UNAVAILABLE` | 漫游策略未允许 | `uci set network.wan.allow_roaming=1; uci commit network; ifup wan` |

**如果 `sipa_eth0` 是 `state DOWN`**，且内核日志里有大量
`sipa-set-rps ... blocked`，说明基带的数据通道没起来：

- **不要用纯 USB 供电（拔掉电池）**。实测无电池冷启动时，CP 的数据面
  （SIPA）不初始化，表现为"显示正常但没网"。插上电池启动即可恢复正常。
- 详见 [FAQ：为什么不能拔电池用](06-faq.md#为什么不能拔电池用)。

---

### Tailscale 连不上别的节点公布的局域网

**现象**：`tailscale status` 正常、能 ping 通节点，但访问对方子网（如 `192.168.99.5`）不通。

**最常见原因**：`tailscale0` 上没有 IPv4 地址（只有 link-local IPv6）。

**检查**：

```sh
ip -4 addr show tailscale0        # 应该有 100.x.x.x/32
ip route get 192.168.99.5         # 应该走 dev tailscale0
tailscale debug prefs | grep RouteAll   # 应该是 true
```

**修复**（`tailscale0` 没地址时）：

```sh
/etc/init.d/tailscale restart
ip -4 addr show tailscale0 | grep inet
```

**还要确认对方节点**：它必须 `tailscale up --advertise-routes=192.168.99.0/24`，
并且控制台里**批准**了这条路由；它自己的 IP 转发和防火墙也要放行。

---

## 屏幕 / 面板

### 信息屏显示 Page load error

**原因**：网页服务（`uhttpd` 的 api 实例）没起来。

**检查**：

```sh
netstat -ltn | grep 8088
logread | grep -i uhttpd | tail -5
```

**处理**：

```sh
/etc/init.d/e5-infoscreen restart
```

如果日志里是 `Unable to open ucode handler`，说明 `uhttpd` 与
`uhttpd-mod-ucode` 版本不匹配——用官方镜像不会出现，自己编译的话请把两者一起升级。

---

### 信号页/状态栏显示"待获取运营商"、信号格是空的

**原因**：面板的逐卡采样服务（`t551m-sim-status`）没数据。

**检查**：

```sh
/etc/init.d/at-service status
/etc/init.d/t551m-sim-status status
ls -l /run/t551m-at6/cmd.sock
ls /tmp/unisoc-modem/sim0/
cat /run/t551m-sims.json
```

**处理**：

```sh
/etc/init.d/at-service restart
/etc/init.d/t551m-sim-status restart
sleep 20
curl -s http://127.0.0.1:8088/api/status | head -c 400
```

`sims` 里 `registration` 应该是 `home`，`operator` 应该是你的运营商。

---

### 信息屏设备信息页全是 `—`、"AT 命令均失败"

**现象**：面板「设备信息」页的调制方式、MCS、BLER、QCI、AMBR、IMEI、IMSI、ICCID
全是 `—`；`/run/t551m-sims.json` 里报 `Invalid or expired AT request`。

**原因**：这块基带**不支持在一行里用 `;` 串联多条 AT 命令**：

```sh
/opt/e5/t551m-at -t 2 'AT+CGSN'                 # 正常
/opt/e5/t551m-at -t 2 'AT+SPACTCARD=0;AT+CGSN'  # +CME ERROR: 65536014
```

旧版脚本把"选卡 + 查询"拼成一条发，于是整轮采集都被拒。

**检查**：

```sh
/opt/e5/t551m-at -t 2 'AT+SPACTCARD=0'      # 期望 OK
/opt/e5/t551m-at -t 2 'AT+CGSN'             # 期望 IMEI + OK
/usr/libexec/t551m-screen-details           # 期望 error:false 且 values 有值
```

**处理**：用本仓库的官方镜像（v1.1.0 起已修复）。手动确认修复是否在位：

```sh
grep -n 'SPACTCARD' /usr/libexec/t551m-screen-details /usr/libexec/t551m-sim-status /usr/libexec/unisoc-modem/cell
```

每个文件里都**不该**再出现 `AT+SPACTCARD=x;...` 这种带分号的写法。

---

### LuCI 首页信号参数空白 / 报 "AT backend did not answer"

**原因**：`mu300dash` 通过 `/usr/libexec/unisoc-modem/at` 分发器取数，
而它的 custom 后端契约是 `<适配器> <超时> <命令>`，`t551m-at` 却要 `-t <秒> <命令>`，
参数对不上就会报 `t551m-at: Unexpected argument`。

**检查**：

```sh
uci get unisoc_modem.main.at_command          # 应该是 .../at-custom
/usr/libexec/unisoc-modem/at -t 5 'AT+COPS?'  # 期望返回运营商 + OK
ubus call mu300dash signal '{"slot":"0"}'     # 期望有 reg / sig
```

**处理**：确认 `at-custom` 转接脚本存在且可执行：

```sh
cat /usr/libexec/unisoc-modem/at-custom
# #!/bin/sh
# exec /opt/e5/t551m-at -t "${1:-5}" "${2:-AT}"

uci set unisoc_modem.main.at_command='/usr/libexec/unisoc-modem/at-custom'
uci commit unisoc_modem
```

`signal` 有 30 秒缓存，改完等一轮再看；`cells` 同理。

---

### SIM2 显示和 SIM1 一模一样（卡槽其实是空的）

**原因**：这块基带的固件**忽略 `AT+SPACTCARD`**——选到卡槽 2 之后，
`AT+CPIN?`、`AT+CIMI`、`AT+CCID` 仍然返回卡槽 1 的数据，于是面板把空槽
显示成和主卡完全一样。

**权威来源是 ModemManager**（所以 LuCI 的 modemmanager 页是对的）：

```sh
mmcli -m 0 | grep -A2 'sim slot paths'
#       sim slot paths: slot 1: /org/.../SIM/0 (active)
#                       slot 2: none
```

**检查补丁是否在位**：

```sh
grep -c mm_slot_present /usr/libexec/t551m-sim-status    # 应为 2
cat /run/t551m-sims.json | head -c 300                   # slot 1 应是 "present": false
```

**处理**：用 v1.1.0 及以后的镜像。手动确认时也可以直接看：

```sh
mmcli -J -m any --timeout=5 | grep -o '"sim-slots":[^]]*]'
# 空槽是 "/"：["/org/freedesktop/ModemManager1/SIM/0", "/"]
```

---

### 内存占用越来越高（跑到 90%+）

**原因**：面板的 WebKit 网络进程（`WPENetworkProcess`）会缓慢泄漏。
实测开机 21 小时后 RSS 达 **790 MB**（`VmData` 72 GB）。

**先确认是不是它**：

```sh
free -m
for d in /proc/[0-9]*; do set -- $(cat $d/statm 2>/dev/null); \
  echo "$(( $2 * 4 )) $(tr '\0' ' ' < $d/cmdline | cut -c1-40)"; done | sort -rn | head -5
```

**立即回收**（约 10 秒，屏幕短暂重绘）：

```sh
/etc/init.d/e5-infoscreen restart
free -m
```

**长期方案**：v1.1.0 起自带 `memguard`，可用内存低于 200 MB 或面板运行超过
6 小时后自动重启面板：

```sh
ps | grep e5-memguard
logread | grep e5-memguard | tail -3
uci show e5-memguard
```

详细数据见 [内存占用](07-memory.md)。

---

### 流量页今日/本月是空的

```sh
/etc/init.d/unisoc-traffic restart
sleep 5
ubus call mu300dash traffic_get '{"slot":"0"}' | head -20
```

---

### 屏幕息屏后是暗灰色，不是全黑

**原因**：背光没被真正关掉（面板黑了但背光还亮着）。

**检查/修复**：

```sh
cat /sys/class/backlight/*/brightness     # 息屏时应该是 0
/usr/libexec/t551m-screen-power set 0
cat /sys/class/backlight/*/brightness     # 应变 0
/usr/libexec/t551m-screen-power set 120   # 恢复
```

如果 `set 0` 报错 `Backlight or touch device missing`，说明系统没识别到触摸设备。

---

## 通话

### 来电没有铃声

```sh
/etc/init.d/e5-ringtone status
ps | grep e5-ringtone
ubus call mu300dash status | head -5
```

重启服务：

```sh
/etc/init.d/e5-ringtone restart
```

日志里应该看到打电话时 `播放铃声`；没有的话看 `logread | grep -i ringtone`。

---

### 接通了没声音

**检查**：

```sh
ps | grep e5-call-audio
cat /run/e5-voice-audio/status.json
logread | grep -i 'call-audio-watch' | tail -5
```

正常通话时日志会有 `VOICE-RUNNING`，挂断后 `VOICE-STOPPED`。

**处理**：

```sh
/etc/init.d/e5-call-audio restart
```

---

### 对方听不到我说话（麦克风）

通话中麦克风增益可能被静音。检查面板上是否按了静音键，或用：

```sh
echo '{"muted": false}' > /run/e5-voice-audio/settings.json
```

（这个文件由 `e5-call-audio-watch` 读取并实时应用。）

---

### 按静音没反应

**原因**：静音是在通话建立**之前**设置的，而通话建立时厂商 profile 会重载，
把静音覆盖掉。

**处理**：通话接通后再按一次静音。新版镜像已修复这个时序问题。

---

### VoLTE：打电话没声音 / 打不进来

**现象**：能响铃，接通后双方都没声音；或者主叫方直接听到"无法接通"。

**原因**：模组 IMS 未注册，而 LYM-10K 的频段只允许 4G/5G（没有 2G/3G 回落），
语音只能走 VoLTE。

**检查**：

```sh
/usr/libexec/unisoc-modem/at 'AT+CIREG?'    # +CIREG: 0,1,0 表示 IMS 未注册
/usr/libexec/unisoc-modem/at 'AT+CSQ'       # 99,99 表示 CS 域无信号
```

**处理**：

1. 先确认这张 SIM 卡**已开通 VoLTE**（打运营商客服问）；
2. 换一张确认支持 VoLTE 的卡试试；
3. 都不行就是基带 IMS 侧的问题，需要进一步调试，可以到 Issues 反馈。

---

## 系统 / 其他

### 网页里 mu300/OTA 等页面 404

**原因**：LuCI 前端资源（`htdocs`）没装全。

**检查**：

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/luci-static/resources/mu300/common.js
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/luci-static/resources/view/mu300/home.js
```

都是 200 就正常；404 说明镜像有问题，请用本仓库的官方镜像。

---

### 想彻底卸载 Linux，恢复成纯 Android

需要把 `e5root` 分区删掉、把 `userdata` 扩回原大小。这属于高级操作：

1. 先在 Linux 里 `e5-next-boot android && reboot` 回到 Android；
2. 用电脑上的 `gdisk`/`parted`（或上游 installer 的卸载功能）删除 `e5root` 分区，
   再把 `userdata` 扩到磁盘末尾；
3. 进 Android 后 `resize.f2fs` 扩容 `/data`。

> 本仓库的刷机脚本**不提供**卸载功能，因为它会改分区表，风险较高。
> 需要的话建议用上游 installer 的 uninstall。

---

### 串口能进但网络不通

串口独立于网络，任何时候都能用。先看：

```sh
ip -4 addr show br-lan          # 应该有 192.168.9.1
ip link show usb0               # 应该是 UP
```

如果没有 `usb0` 或 `br-lan` 没地址：

```sh
/etc/init.d/network restart
```

---

## 还是解决不了？

到本仓库的 [Issues](../../issues) 提问，请附上：

1. 机型和固件版本（`adb shell getprop ro.build.display.id`）；
2. 你执行的命令和**完整报错**；
3. 相关日志：
   ```sh
   logread | tail -100
   dmesg | tail -100
   ```
4. 如果是启动问题，附串口日志。

信息越全，定位越快。
