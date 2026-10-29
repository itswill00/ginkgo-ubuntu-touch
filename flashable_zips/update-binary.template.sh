#!/sbin/sh
#
# Ubuntu Touch 20.04 / Halium 10 installer for the Xiaomi Redmi Note 8 (ginkgo).
#
# ginkgo is A-only and has a real, non-dynamic system partition, so this installer
# is much smaller than a GKI port's: there is no super partition to resize, no
# slot suffix to resolve, and no separate vendor_dlkm image to merge. It writes
# three partitions and sets up /data.
#
# What it does, in order:
#   1. identify the device and refuse to run on anything else
#   2. back up the current boot, dtbo and vbmeta images to /sdcard
#   3. disable dm-verity and AVB on vbmeta so the kernel and system may be replaced
#   4. write boot.img, dtbo.img and system.img
#   5. prepare /data for an unencrypted ext4 Ubuntu Touch rootfs
#   6. record which build was installed
#
# It does not touch /data unless FORMAT_DATA=1 is set.

set -e

# ---------------------------------------------------------------------------
# Recovery environment

OUTFD=""
for fd in 1 2 3; do
    if [ -e "/proc/self/fd/$fd" ]; then OUTFD="$fd"; break; fi
done

ui_print() { echo "ui_print $*" > "/proc/self/fd/$OUTFD"; }
ui_print_raw() { echo "$*" >> "/proc/self/fd/$OUTFD"; }
abort() { ui_print "! $*"; ui_print_raw "abort"; exit 1; }

# Busybox in recovery does not always provide these.
command -v getprop >/dev/null 2>&1 || getprop() { echo ""; }

WORK=/tmp/tanzanite-installer
FORCE=0
FORMAT_DATA=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --format-data) FORMAT_DATA=1 ;;
    esac
done

# ---------------------------------------------------------------------------
ui_print " "
ui_print "Ubuntu Touch 20.04 (Halium 10)"
ui_print "Xiaomi Redmi Note 8 (ginkgo)"
ui_print " "

# ---------------------------------------------------------------------------
# 1. Device check

DEVICE="$(getprop ro.product.device)"
if [ -z "$DEVICE" ]; then
    for p in /dev/block/by-name/boot /dev/block/bootdevice/by-name/boot; do
        [ -e "$p" ] && DEVICE="$(getprop ro.boot.device)" && break
    done
fi

case "$DEVICE" in
    ginkgo|willow)
        ui_print "- Device: $DEVICE"
        ;;
    "")
        ui_print "! Cannot determine device codename."
        ui_print "! Refusing to continue without knowing the target."
        [ "$FORCE" = "1" ] || abort "pass --force to install anyway"
        ui_print "! Continuing because --force was given."
        ;;
    *)
        ui_print "! This package is for ginkgo (Redmi Note 8) and willow (8T)."
        ui_print "! Found: $DEVICE"
        [ "$FORCE" = "1" ] || abort "wrong device"
        ui_print "! Continuing because --force was given."
        ;;
esac

# ---------------------------------------------------------------------------
# 2. Locate partitions
#
# ginkgo is A-only, so the names have no slot suffix. by-name is preferred; the
# bootdevice symlink tree is the fallback for recoveries that do not populate it.

find_part() {
    for base in /dev/block/by-name /dev/block/bootdevice/by-name; do
        if [ -e "$base/$1" ]; then
            echo "$base/$1"
            return 0
        fi
    done
    return 1
}

BOOT_PART="$(find_part boot)"     || abort "boot partition not found"
SYSTEM_PART="$(find_part system)" || abort "system partition not found"
DTBO_PART="$(find_part dtbo)"     || abort "dtbo partition not found"
VBMETA_PART="$(find_part vbmeta)" || abort "vbmeta partition not found"

ui_print "- boot   : $BOOT_PART"
ui_print "- system : $SYSTEM_PART"
ui_print "- dtbo   : $DTBO_PART"
ui_print "- vbmeta : $VBMETA_PART"

mkdir -p "$WORK"

# ---------------------------------------------------------------------------
# 3. Back up what is about to be replaced

BACKUP=/sdcard/.ginkgo-backup-$(date +%Y%m%d-%H%M%S)
ui_print " "
ui_print "- Backing up current images to $BACKUP"
mkdir -p "$BACKUP" 2>/dev/null || {
    ui_print "! /sdcard is not mounted; skipping backup."
    BACKUP=""
}

if [ -n "$BACKUP" ]; then
    for pair in "boot:$BOOT_PART" "dtbo:$DTBO_PART" "vbmeta:$VBMETA_PART"; do
        name="${pair%%:*}"
        part="${pair#*:}"
        # Read only as much as the partition reports, not the whole device.
        size="$(blockdev --getsize64 "$part" 2>/dev/null || echo 0)"
        if [ "$size" -gt 0 ]; then
            dd if="$part" of="$BACKUP/$name.img" bs=4M count=$((size / 4194304 + 1)) \
                2>/dev/null || ui_print "! could not back up $name"
        fi
    done
    ui_print "- Backup written."
fi

# ---------------------------------------------------------------------------
# 4. Disable dm-verity and AVB
#
# The stock vbmeta carries verification flags. Writing a kernel and system that
# were not signed by Xiaomi means the bootloader will refuse to boot unless
# verification is disabled. Flag bit 0 disables AVB, bit 1 disables dm-verity;
# both are needed, and the flags live at offset 123 of the vbmeta image.

ui_print " "
ui_print "- Disabling AVB and dm-verity on vbmeta"

dd if="$VBMETA_PART" of="$WORK/vbmeta.img" bs=4096 2>/dev/null || \
    abort "cannot read vbmeta"

if [ ! -s "$WORK/vbmeta.img" ]; then
    abort "vbmeta read produced an empty image"
fi

# The AVB header stores flags as a big-endian uint32 at offset 120.
printf '\000\000\000\003' | dd of="$WORK/vbmeta.img" bs=1 seek=120 conv=notrunc 2>/dev/null || \
    abort "cannot write vbmeta flags"

blockdev --setrw "$VBMETA_PART" 2>/dev/null || true
dd if="$WORK/vbmeta.img" of="$VBMETA_PART" bs=4096 2>/dev/null || \
    abort "cannot write vbmeta"
sync
ui_print "- vbmeta updated."

# ---------------------------------------------------------------------------
# 5. Write the images

ui_print " "
IMGDIR=""
for d in "$(dirname "$0")/images" /tmp/images "$WORK/images"; do
    [ -d "$d" ] && IMGDIR="$d" && break
done
[ -n "$IMGDIR" ] || abort "image directory not found in the package"
ui_print "- Images: $IMGDIR"

write_image() {
    name="$1"; part="$2"
    src="$IMGDIR/$name.img"
    [ -s "$src" ] || abort "$name.img missing from package"

    srcsize="$(stat -c%s "$src" 2>/dev/null || echo 0)"
    partsize="$(blockdev --getsize64 "$part" 2>/dev/null || echo 0)"
    ui_print "- $name: ${srcsize} bytes -> ${partsize} bytes"
    if [ "$partsize" -gt 0 ] && [ "$srcsize" -gt "$partsize" ]; then
        abort "$name.img is larger than the $name partition"
    fi

    umount -f "$part" 2>/dev/null || true
    blockdev --setrw "$part" 2>/dev/null || true
    dd if="$src" of="$part" bs=4M 2>/dev/null || abort "failed writing $name"
    sync
}

write_image boot   "$BOOT_PART"
write_image dtbo   "$DTBO_PART"
write_image system "$SYSTEM_PART"

# ---------------------------------------------------------------------------
# 6. Prepare /data
#
# Ubuntu Touch keeps its rootfs on /data/ubuntu. It must be ext4 and unencrypted:
# the Halium initramfs mounts it directly, and a metadata-encrypted or F2FS
# userdata will not mount. This is destructive, so it only happens on request.

DATA_PART="$(find_part userdata || find_part data || true)"

if [ -n "$DATA_PART" ]; then
    if [ "$FORMAT_DATA" = "1" ]; then
        ui_print " "
        ui_print "- Formatting $DATA_PART as ext4 (this erases all user data)"
        umount -f "$DATA_PART" 2>/dev/null || true
        # Zero the first and last megabyte: that clears the F2FS superblock and
        # the FBE metadata footer, which mkfs.ext4 alone does not remove.
        dd if=/dev/zero of="$DATA_PART" bs=1M count=1 2>/dev/null || true
        size="$(blockdev --getsize64 "$DATA_PART" 2>/dev/null || echo 0)"
        if [ "$size" -gt 2097152 ]; then
            dd if=/dev/zero of="$DATA_PART" bs=1M seek=$((size / 1048576 - 1)) count=1 2>/dev/null || true
        fi
        mke2fs -t ext4 -b 4096 -F "$DATA_PART" 2>/dev/null || abort "mkfs.ext4 failed"
        ui_print "- /data formatted."
    else
        ui_print " "
        ui_print "- /data left untouched."
        ui_print "  If this is a fresh install and the device does not boot,"
        ui_print "  re-run with --format-data to get an unencrypted ext4 /data."
    fi
else
    ui_print "! userdata partition not found; /data was not prepared."
fi

# ---------------------------------------------------------------------------
# 7. Record the build

mkdir -p /sdcard 2>/dev/null || true
if [ -s "$IMGDIR/../build-info.txt" ]; then
    cp "$IMGDIR/../build-info.txt" /sdcard/ginkgo-installed.txt 2>/dev/null || true
    ui_print " "
    ui_print "- Installed build:"
    while IFS= read -r line; do ui_print "    $line"; done < "$IMGDIR/../build-info.txt"
fi

# ---------------------------------------------------------------------------
ui_print " "
ui_print "- Done. Reboot to system."
ui_print " "
