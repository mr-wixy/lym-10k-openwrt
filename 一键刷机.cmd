@echo off
rem 一键刷机入口：双击运行。
rem 请求管理员权限（写分区表需要），执行完保持窗口打开，出错也能看到原因。
setlocal
cd /d "%~dp0"

rem 已提权则直接跑，否则用 UAC 重新启动自己
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限，正在请求...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%*'"
    exit /b
)

title LYM-10K 一键刷机
echo ============================================================
echo  LYM-10K 刷 OpenWrt（机身存储，与 Android 双系统共存）
echo ============================================================
echo.
echo  手机请先：开机进入 Android、插好 USB、开启 USB 调试。
echo.
echo  1 = 先检查计划，不写手机（推荐第一次先跑这个）
echo  2 = 直接刷入
echo.
set /p CHOICE=请选择 [1/2，回车默认 1]：

if "%CHOICE%"=="2" (
    set "ARGS="
) else (
    set "ARGS=-DryRun"
)

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-openwrt.ps1" %ARGS%
set RC=%errorlevel%

echo.
echo ============================================================
if %RC% equ 0 (
    echo  完成。手机正在重启进入 e5-linux，约 90 秒后亮屏。
) else (
    echo  执行失败（退出码 %RC%）。
    echo  把上面的完整输出发给开发者，或查看 docs/05-troubleshooting.md
)
echo ============================================================
echo.
pause