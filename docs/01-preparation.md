# 刷机前必读：解锁、Root 和电脑环境

这一步只需要做一次。做完之后，以后每次刷机只要跑一个脚本。

> ⚠️ **解锁 bootloader 会清空手机全部数据**（相当于恢复出厂设置）。
> 请先把照片、聊天记录等需要的东西备份出来。

---

## 1. 解锁 bootloader

LYM-10K 是展锐（Unisoc）平台，解锁方式与主流高通/联发科机型不同。常见做法：

1. 手机进入「设置 → 关于手机」，连续点击「版本号」直到开启**开发者选项**；
2. 「开发者选项」里打开 **USB 调试** 和 **OEM 解锁**（如果这一项是灰的，
   说明需要先连一次网络并登录账号）；
3. 手机关机，按住「音量上 + 电源」进入 **fastboot / bootloader** 模式；
4. 电脑装好 adb 后执行：

   ```powershell
   adb devices            # 应先看到手机
   adb reboot bootloader
   fastboot devices       # bootloader 模式下也能看到设备
   fastboot flashing unlock
   ```

5. 手机屏幕上会出现确认提示，用音量键选 **Yes**、电源键确认。
   手机会自动重启并清空数据。

> 不同批次/固件的 LYM-10K 可能：

- 需要先申请解锁码（展锐机型较常见）；
- 或者 fastboot 命令名不同（`fastboot oem unlock`）。

如果卡在这一步，请到 Issues 里贴出你的 **固件版本号** 和 **fastboot 报错原文**。

---

## 2. 安装 Magisk 获得 Root

刷机脚本需要 root 权限来改分区。

1. 电脑安装 **Magisk** App（官方 GitHub 下载最新版）；
2. 用 `adb push` 把手机原厂的 `boot.img` 拷到手机，在 Magisk App 里
   「安装 → 选择并修补一个文件」，生成 `magisk_patched-*.img`；
3. 把修补后的镜像 `adb pull` 回电脑，然后：

   ```powershell
   adb reboot bootloader
   fastboot flash boot magisk_patched-*.img
   fastboot reboot
   ```

4. 开机后打开 Magisk，确认「已安装」；
5. **重要**：Magisk → 设置 → 超级用户 → 把「Shell」的权限设为允许
   （需要 Magisk 里出现 `su` 请求时点允许，或在设置里预授权）。

验证 root 是否可用：

```powershell
adb shell su -c id
# 期望输出：uid=0(root) gid=0(root) ...
```

如果输出 `Permission denied`，说明 Magisk 没给 shell 授权，请回到第 5 步。

---

## 3. 电脑环境

### 3.1 adb

- Windows：下载 [platform-tools](https://developer.android.com/studio/releases/platform-tools)，
  解压后把目录加入 `PATH`；
- 或者用 `winget install Google.PlatformTools`。

验证：

```powershell
adb version
adb devices        # 手机上会弹「允许 USB 调试」，点允许
```

### 3.2 不需要装 Python

**这一步可以跳过。** 早期版本的刷机脚本用 Python 计算分区表，现在已改成纯 PowerShell，
Windows 10/11 自带就能跑，**不用安装 Python、Node 或任何其他环境**。

### 3.3 关闭杀毒软件的脚本拦截（如有）

个别安全软件会拦截 `.ps1` 脚本或含 `dd`/`boot` 字样的操作。
如果脚本一闪而过、或提示被拦截，请把解压目录加入白名单。

---

## 4. 检查清单

刷机前逐项确认：

- [ ] bootloader 已解锁（开机第一屏有 "unlocked" 提示，或 `fastboot getvar unlocked` 返回 yes）
- [ ] Magisk 已安装，`adb shell su -c id` 返回 uid=0
- [ ] `adb devices` 能看到设备
- [ ] 手机电量 > 50%
- [ ] 重要数据已备份
- [ ] 手机当前运行在 **Android**（不是 Linux）

都打勾了，就可以进入 [一键刷机](02-flash.md)。
