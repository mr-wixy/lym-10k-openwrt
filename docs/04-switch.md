# 双系统切换

刷好之后，手机里同时有 Android 和 OpenWrt，开机时二选一。

---

## Android → Linux（手机上点一下）

1. 在 Android 里打开 **Magisk**；
2. 底部切到「**模块**」；
3. 找到 **`LYM-10K Boot Linux`**；
4. 点它右侧的 **Action（▶ 播放按钮）**；
5. 手机会自动重启，约 90 秒进入 OpenWrt。

> 第一次装完 Magisk 模块后，要**先进一次 Android** 让它生效，Action 按钮才会出现。

如果点了没反应，看日志：

```powershell
adb shell su -c "cat /data/local/tmp/lym10k-boot-linux.log"
```

正常应该有：

```
2026-11-16 12:45:36 misc=/dev/block/by-name/misc
2026-11-16 12:45:37 slot b armed; rebooting into Linux
```

---

## Linux → Android（一条命令）

在 OpenWrt 里（SSH、串口、或 LuCI 的终端）：

```sh
e5-next-boot android && reboot
```

手机会重启进入 Android。

---

## 想固定用某一个系统

- **固定 Linux**：不要点 Magisk 的 Action 就行（Android 只是"待着"，不会自动抢）。
- **固定 Android**：在 Linux 里执行 `e5-next-boot android` 后重启即可；
  之后不要再点 Action。

---

## 切换是怎么实现的

手机里有 A/B 两个启动槽位：

| 槽位 | 系统 |
|---|---|
| slot **a** | Android |
| slot **b** | Linux（`boot_b` 里的启动镜像） |

- 点 Magisk Action = 把 `misc` 分区里的 bootloader 控制块写成"下次启动 b 槽位"，
  并只在这次生效（tries=2，起不来会自动回落到 a 槽位 Android）。
- `e5-next-boot android` = 反过来，让下次启动 a 槽位。

两个系统各自有独立分区：Android 在 `super`/`userdata`，Linux 在 `e5root`，
**互不覆盖**。

---

## 常见疑问

**Q：切换会不会丢数据？**
不会。两个系统的数据分别在各自分区，切换只是改"下次从哪启动"。

**Q：能一直只用 Linux，把 Android 删掉吗？**
可以但没必要。Android 留着当"救生艇"更安全——万一 Linux 起不来，
它会自动回到 Android。

**Q：Action 点了没反应？**
Magisk 需要给 `shell` 授予超级用户权限（Magisk 设置 → 超级用户），
否则写 `misc` 会失败。
