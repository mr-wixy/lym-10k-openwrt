#!/system/bin/sh
# 一键切到 Linux：把 bootloader_control 的 slot b 条目写成"武装"状态，然后重启。
#
# 这段 32 字节由 e5-linux 的 boot/build-boot-image.py 生成
# （boot-linux-slotb-release.misc-slot-b-trial.bin），内容为：
#   5f620000 42434142 0102 0000 9e00 2f00 ... 9bf8546d
# 写入位置：misc 分区偏移 2048。
#
# 写完后会读回校验；校验不过则不重启，避免把机器留在半武装状态。

BLOCK_B64='X2IAAEJDQUIBAgAAngAvAAAAAAAAAAAAAAAAAJv4VG0='
LOG=/data/local/tmp/lym10k-boot-linux.log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

MISC=
for c in /dev/block/by-name/misc /dev/block/mmcblk0p3; do
    [ -b "$c" ] && MISC=$c && break
done
if [ -z "$MISC" ]; then
    log "ERROR: misc partition not found"
    exit 1
fi
log "misc=$MISC"

echo "$BLOCK_B64" | base64 -d > /data/local/tmp/e5-bc-b.bin || {
    log "ERROR: cannot decode block"
    exit 1
}
dd if=/data/local/tmp/e5-bc-b.bin of="$MISC" bs=1 seek=2048 conv=notrunc 2>/dev/null || {
    log "ERROR: dd failed"
    exit 1
}
sync

# 读回校验
dd if="$MISC" bs=1 skip=2048 count=32 of=/data/local/tmp/e5-bc-read.bin 2>/dev/null
if cmp -s /data/local/tmp/e5-bc-b.bin /data/local/tmp/e5-bc-read.bin; then
    log "slot b armed; rebooting into Linux"
    rm -f /data/local/tmp/e5-bc-b.bin /data/local/tmp/e5-bc-read.bin
    sync
    reboot
else
    log "ERROR: misc verify failed, not rebooting"
    exit 1
fi
