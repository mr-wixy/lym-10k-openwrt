# 第一次启动：联网、进网页、改密码

手机重启后：

1. 黑屏几秒 → 出现开机 logo；
2. 约 60–90 秒后，屏幕上出现**信息屏**（时间、运营商、信号格、电量）；
3. 说明系统已经跑起来了。

---

## 1. 用 USB 连电脑

把手机用 USB 线插到电脑上，电脑会多出一个网卡（名称类似 `UsbNcm Host Device`）。

打开「网络连接」，给这个网卡设置固定 IP：

| 项 | 值 |
|---|---|
| IP 地址 | `192.168.9.2` |
| 子网掩码 | `255.255.255.0` |
| 网关 | 留空 |
| DNS | 留空 |

然后浏览器打开 <http://192.168.9.1/>，应该能看到 LuCI 登录页。

> 打不开？见 [排障：网页打不开](05-troubleshooting.md#网页打不开)。

---

## 2. 改 root 密码（建议）

默认 root 没有密码（串口直连可用）。用 SSH 登录后设置：

```sh
ssh root@192.168.9.1
passwd root
```

或者网页 LuCI → 系统 → 管理权 → 设置密码。

---

## 3. 连 Wi-Fi

手机自己会开热点：

| 项 | 值 |
|---|---|
| SSID | `LYM-10K` |
| 密码 | `12345678` |
| 频段 | 5 GHz（ch149 / VHT80） |

用手机或电脑连上这个 Wi-Fi，就能访问 <http://192.168.9.1/>，不占用 USB 线。

想改名字/密码：LuCI → 网络 → 无线，或 SSH：

```sh
uci set wireless.default_radio0.ssid='我的热点'
uci set wireless.default_radio0.key='新密码'
uci commit wireless && wifi reload
```

---

## 4. 蜂窝网络

开机自动拨号，不需要手动操作。检查是否联网：

```sh
ubus call network.interface.wan status | grep -E '"up"|"address"'
ip -4 addr show sipa_eth0
ping -c2 223.5.5.5
```

如果 `up` 是 false，见 [排障：没有网络](05-troubleshooting.md#蜂窝没有网络)。

---

## 5. 装软件

系统自带 `apk` 包管理器（OpenWrt 25.12）：

```sh
apk update
apk add htop          # 举例
```

> 注意：这台机器更换了定制内核，**不要安装 `kmod-*` 内核模块包**
> （那些是给官方 6.12 内核编译的，装不上也用不了）。

---

## 6. 串口（可选，排障用）

如果你有 USB-TTL 串口线：

| 项 | 值 |
|---|---|
| 波特率 | 115200 |
| 引脚 | 板上有标注（TX/RX/GND） |
| 登录 | 直接 root，无密码 |

串口在任何时候都能用（包括系统起不来时），是最后的救命通道。

---

## 7. 日常使用小结

| 想做什么 | 怎么做 |
|---|---|
| 看信号/流量/短信 | 手机屏幕上的信息屏 |
| 改设置、装插件 | 浏览器 <http://192.168.9.1/> |
| 命令行 | `ssh root@192.168.9.1` |
| 切回 Android | `e5-next-boot android && reboot` |
| 从 Android 切回来 | Magisk → 模块 → LYM-10K Boot Linux → Action |
