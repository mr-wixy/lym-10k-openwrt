# LYM-10K Boot Linux (Magisk)

装好本模块后，在 Magisk 应用里点模块右侧的「Action」按钮：

1. 写入 misc 的 bootloader_control（武装 slot b，一次性，tries=2）
2. 读回校验
3. 校验通过则重启，进入 e5-linux（OpenWrt）

回到 Android：在 Linux 里执行 `e5-next-boot android && reboot`。

日志：`/data/local/tmp/lym10k-boot-linux.log`
