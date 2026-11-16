#!/usr/bin/env python3
"""鍦ㄧ數鑴戜笂缂栬緫鎵嬫満 eMMC 鐨?GPT锛堥€氳繃 adb 璇诲啓锛屼笉闇€瑕佹墜鏈轰晶鐨勪换浣曞垎鍖哄伐鍏凤級銆?
鐢ㄩ€旓細鎶?userdata 缂╁埌鎸囧畾澶у皬锛屽苟鍦ㄥ叾鍚庣殑绌洪棽绌洪棿鍒涘缓 e5root 鍒嗗尯锛?渚?e5-linux 鐨?boot/init 鐩存帴鍚姩锛堝畠鎸?GPT 鍒嗗尯鍚?e5root 鏌ユ壘锛夈€?
    python gpt_carve.py --serial <adb 搴忓垪鍙? --userdata-sectors 36950016 --dry-run
    python gpt_carve.py --serial <adb 搴忓垪鍙? --userdata-sectors 36950016

GPT 甯冨眬锛歀BA1 澶淬€丩BA2..33 鏉＄洰琛紱澶囦唤鍦ㄧ鐩樻湯灏撅紙鏉＄洰琛?+ 澶达級銆?涓ゅ閮借鏀癸紝骞堕噸绠楁潯鐩〃 CRC32 涓庡ご CRC32銆?"""
import argparse
import base64
import struct
import subprocess
import sys
import zlib

SECTOR = 512
ENTRY_SIZE = 128
ENTRIES_SECTORS = 32                      # 128 椤?脳 128 B = 16 KiB
LINUX_FS = bytes.fromhex('af3dc60f838472478e793d69d8477de4')  # Linux filesystem


def adb(serial, *args, binary=False):
    cmd = ['adb'] + (['-s', serial] if serial else []) + list(args)
    out = subprocess.run(cmd, capture_output=True, check=True).stdout
    return out if binary else out.decode('utf-8', 'replace')


def shell(serial, command):
    return adb(serial, 'shell', command)


def read_bytes(serial, skip, count):
    b64 = shell(serial, f"su -c 'dd if=/dev/block/mmcblk0 bs=512 skip={skip} count={count} 2>/dev/null | base64'").strip()
    return base64.b64decode(b64)


def write_bytes(serial, skip, data):
    b64 = base64.b64encode(data).decode()
    shell(serial, f"su -c 'echo {b64} | base64 -d | dd of=/dev/block/mmcblk0 bs=512 seek={skip} conv=notrunc 2>/dev/null'")


def read_gpt(serial):
    head = read_bytes(serial, 1, 1)
    entries = read_bytes(serial, 2, ENTRIES_SECTORS)
    backup_entries = read_bytes(serial, None, 0) if False else None
    # 纾佺洏鏈熬浣嶇疆浠庡ご閲岀畻
    backup_lba = struct.unpack_from('<Q', head, 32)[0]
    disk_lba = backup_lba
    first_usable, last_usable = struct.unpack_from('<QQ', head, 40)
    backup_entries = read_bytes(serial, backup_lba - ENTRIES_SECTORS, ENTRIES_SECTORS)
    backup_head = read_bytes(serial, backup_lba, 1)
    return dict(head=head, entries=entries, backup_entries=backup_entries,
                backup_head=backup_head, backup_lba=backup_lba, disk_lba=disk_lba,
                first_usable=first_usable, last_usable=last_usable)


def parse_entries(entries):
    out = []
    for i in range(len(entries) // ENTRY_SIZE):
        e = entries[i * ENTRY_SIZE:(i + 1) * ENTRY_SIZE]
        if e[:16] == b'\0' * 16:
            out.append(None)
            continue
        typ = e[:16]
        first, last = struct.unpack_from('<QQ', e, 32)
        name = e[56:128].decode('utf-16-le').rstrip('\0')
        out.append(dict(index=i, type=typ, first=first, last=last, name=name, raw=e))
    return out


def build_entry(typ, first, last, name, guid=b'\0' * 16):
    e = bytearray(ENTRY_SIZE)
    e[0:16] = typ
    e[16:32] = guid
    struct.pack_into('<QQ', e, 32, first, last)
    n = name.encode('utf-16-le')[:72]
    e[56:56 + len(n)] = n
    return bytes(e)


def fix_crc(head, entries):
    h = bytearray(head)
    struct.pack_into('<I', h, 88, zlib.crc32(entries) & 0xffffffff)   # entries CRC
    struct.pack_into('<I', h, 16, 0)                                   # header CRC field
    struct.pack_into('<I', h, 16, zlib.crc32(bytes(h[:92])) & 0xffffffff)
    return bytes(h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--serial', default='')
    ap.add_argument('--userdata-sectors', type=int, default=0)
    ap.add_argument('--name', default='e5root')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--print-offset', metavar='NAME', default='',
                    help='只打印该分区起始字节并退出')
    a = ap.parse_args()

    g = read_gpt(a.serial)
    ents = parse_entries(g['entries'])
    if a.print_offset:
        e = next((x for x in ents if x and x['name'] == a.print_offset), None)
        if not e:
            sys.exit('partition %s not found' % a.print_offset)
        print(e['first'] * SECTOR)
        return
    if not a.userdata_sectors:
        sys.exit('--userdata-sectors is required')
    ud = next((e for e in ents if e and e['name'] == 'userdata'), None)
    if not ud:
        sys.exit('no userdata partition')
    existing = next((e for e in ents if e and e['name'] == a.name), None)
    if existing:
        info = "%s already exists at %d..%d (%d MiB)" % (
            a.name, existing['first'], existing['last'],
            (existing['last'] - existing['first'] + 1) // 2048)
        if a.dry_run:
            print(info)
            print("userdata: %d..%d" % (ud['first'], ud['last']))
            return
        sys.exit(info)

    new_last = ud['first'] + a.userdata_sectors - 1
    if new_last >= ud['last']:
        sys.exit('new userdata is not smaller')
    if new_last > g['last_usable']:
        sys.exit('userdata would exceed the last usable LBA')

    root_first = new_last + 1
    root_last = g['last_usable']
    root_sectors = root_last - root_first + 1
    if root_sectors < 2 * 1024 * 1024:      # 鑷冲皯 1 GiB
        sys.exit(f'not enough space for {a.name}: {root_sectors} sectors')

    print(f"userdata: {ud['first']}..{ud['last']} -> {ud['first']}..{new_last} "
          f"({a.userdata_sectors} sectors, {a.userdata_sectors // 2048} MiB)")
    print(f"{a.name}: {root_first}..{root_last} ({root_sectors} sectors, {root_sectors // 2048} MiB)")

    if a.dry_run:
        return

    entries = bytearray(g['entries'])
    struct.pack_into('<Q', entries, ud['index'] * ENTRY_SIZE + 40, new_last)
    slot = next(i for i, e in enumerate(ents) if e is None)
    entries[slot * ENTRY_SIZE:(slot + 1) * ENTRY_SIZE] = build_entry(LINUX_FS, root_first, root_last, a.name)
    entries = bytes(entries)

    head = fix_crc(g['head'], entries)
    backup_head = fix_crc(g['backup_head'], entries)

    write_bytes(a.serial, 1, head)
    write_bytes(a.serial, 2, entries)
    write_bytes(a.serial, g['disk_lba'] - ENTRIES_SECTORS, entries)
    write_bytes(a.serial, g['disk_lba'], backup_head)
    shell(a.serial, "su -c sync")

    # 璇诲洖鏍￠獙锛堝彧姣斿ご閮ㄤ笌鏉＄洰琛級
    check = read_gpt(a.serial)
    ok = (check['head'] == head and check['entries'] == entries and
          check['backup_entries'] == entries and check['backup_head'] == backup_head)
    print('verify:', 'OK' if ok else 'MISMATCH')
    if not ok:
        sys.exit(1)
    print(f'e5root offset bytes = {root_first * SECTOR}')


if __name__ == '__main__':
    main()


