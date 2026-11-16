#!/usr/bin/env bash
# 准备一键刷机用的 e5root 镜像：
#   - 以 out/sd/e5-openwrt-lym10k.ext4 为源
#   - 预置 /etc/e5/part-root 与 /etc/e5/part-autoboot（让 boot/init 认这个分区）
#   - 去掉 sd-root 标记（那是 TF 卡用的）
# 产物：out/firmware/e5root.ext4(.gz)
set -eu
export DOCKER_CONFIG="$HOME/.docker-cli"
SRC=/mnt/d/Code/lym-10k/out/sd/e5-openwrt-lym10k.ext4
DST=/mnt/d/Code/lym-10k/out/firmware/e5root.ext4

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
mkdir -p /mnt/d/Code/lym-10k/out/firmware
cp -f "$SRC" "$DST"

docker run --rm --privileged --platform linux/amd64 -v "$DST":/img.ext4 alpine:3.22 sh -euc '
apk add --no-cache e2fsprogs >/dev/null 2>&1 || true
mkdir -p /mnt/r
mount -o loop,rw /img.ext4 /mnt/r
mkdir -p /mnt/r/etc/e5
: > /mnt/r/etc/e5/part-root
: > /mnt/r/etc/e5/part-autoboot
rm -f /mnt/r/etc/e5/sd-root /mnt/r/etc/e5/sd-root.off
sync
ls -l /mnt/r/etc/e5/part-root /mnt/r/etc/e5/part-autoboot
umount /mnt/r
e2fsck -fn /img.ext4 2>&1 | tail -2
'
ls -l "$DST"
