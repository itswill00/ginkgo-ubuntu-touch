#!/bin/bash
# Build boot.img, dtbo.img and the device tarball, then the rootfs and system.img.
#
# This deliberately does not call halium-generic-adaptation-build-tools/build.sh.
# That script's first act is to build the kernel with the AOSP x86_64 prebuilt
# clang, which cannot run on an aarch64 host, and the kernel is already built by
# build-kernel-native.sh. Instead this runs the individual stage scripts, which
# are the same ones build.sh would have run after its kernel stage:
#
#   make-dtboimage.sh            dtbo.img from the kernel's DTBO
#   make-bootimage.sh            boot.img, including the AVB hash footer
#   build-tarball-mainline.sh    device_<codename>.tar.xz (the rootfs overlay)
#   prepare-fake-ota.sh          focal rootfs + generic system image
#   system-image-from-ota.sh     system.img
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"

WORKSPACE="${WORKSPACE:-$REPO/build-workspace}"
DOWN="${DOWN:-$WORKSPACE/downloads}"
KERNEL_OBJ="${KERNEL_OBJ:-$WORKSPACE/KERNEL_OBJ}"
BUILD_TOOLS="${BUILD_TOOLS:-$WORKSPACE/build-tools}"
WORK="${WORK:-$WORKSPACE/tools-work}"
OUT="${OUT:-$REPO/out}"

die() { printf '\n\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# ---------------------------------------------------------------------------
step "Checking inputs"

[ -d "$BUILD_TOOLS" ] || die "adaptation tools missing at $BUILD_TOOLS"
[ -s "$KERNEL_OBJ/arch/arm64/boot/Image.gz-dtb" ] || \
    die "kernel not built: $KERNEL_OBJ/arch/arm64/boot/Image.gz-dtb missing"
for t in android_system_tools_mkbootimg/mkbootimg.py avb/avbtool \
         libufdt/utils/src/mkdtboimg.py halium-boot-ramdisk.img; do
    [ -e "$DOWN/$t" ] || die "missing $DOWN/$t (run scripts/prepare-image-tools.sh)"
done
note "ok"

mkdir -p "$OUT" "$WORK"
# The staging tree must start empty: build-tarball-mainline.sh copies the overlay
# into it and aborts if both /opt/halium-overlay and /usr/share/halium-overlay are
# present, so leftovers from a previous run would make a correct tree fail.
rm -rf "$WORK/tmp" "$WORK/system"
mkdir -p "$WORK/tmp/partitions" "$WORK/system"

# The stage scripts read deviceinfo and the overlay from the current directory,
# and expect the kernel and downloaded tools under the TMPDOWN they are given.
cp "$REPO/deviceinfo" "$WORK/deviceinfo"
rm -rf "$WORK/overlay"
cp -a "$REPO/overlay" "$WORK/overlay"
# make-bootimage.sh resolves deviceinfo_bootimg_prebuilt_dtb relative to the
# directory holding deviceinfo, so the kernel object tree has to be reachable
# from there by that name.
ln -sfn "$KERNEL_OBJ" "$WORK/KERNEL_OBJ"

# ---------------------------------------------------------------------------
step "dtbo.img"
( cd "$WORK" && "$BUILD_TOOLS/make-dtboimage.sh" "$DOWN" "$KERNEL_OBJ" "$OUT/dtbo.img" )
[ -s "$OUT/dtbo.img" ] || die "dtbo.img not produced"
note "$(stat -c%s "$OUT/dtbo.img") bytes"

# ---------------------------------------------------------------------------
step "boot.img"
# make-bootimage.sh resolves the DTBO relative to the directory holding OUT, so
# dtbo.img has to be next to boot.img - which it is, both are in $OUT.
mkdir -p "$WORK/system"
( cd "$WORK" && "$BUILD_TOOLS/make-bootimage.sh" \
    "$DOWN" "$KERNEL_OBJ" "$DOWN/halium-boot-ramdisk.img" "$OUT/boot.img" "$WORK/system" )
[ -s "$OUT/boot.img" ] || die "boot.img not produced"
note "$(stat -c%s "$OUT/boot.img") bytes"

# ---------------------------------------------------------------------------
step "Device tarball"
# build-tarball-mainline.sh expects boot.img under <dir>/partitions/, which is
# where build.sh would have put it.
mkdir -p "$WORK/tmp/partitions"
cp "$OUT/boot.img" "$WORK/tmp/partitions/boot.img"
( cd "$WORK" && "$BUILD_TOOLS/build-tarball-mainline.sh" \
    "$(sed -n 's/^deviceinfo_codename="\(.*\)"/\1/p' "$REPO/deviceinfo")" \
    "$OUT" "$WORK/tmp" "usrmerge" )

TARBALL="$OUT/device_$(sed -n 's/^deviceinfo_codename="\(.*\)"/\1/p' "$REPO/deviceinfo").tar.xz"
[ -s "$TARBALL" ] || die "device tarball not produced"
note "$(stat -c%s "$TARBALL") bytes"

# ---------------------------------------------------------------------------
step "Rootfs and system image"
rm -rf "$WORKSPACE/ota"
( cd "$WORK" && "$BUILD_TOOLS/prepare-fake-ota.sh" "$TARBALL" "$WORKSPACE/ota" )
( cd "$WORK" && "$BUILD_TOOLS/system-image-from-ota.sh" \
    "$WORKSPACE/ota/ubuntu_command" "$OUT" )

[ -s "$OUT/system.img" ] || die "system.img not produced"
note "$(stat -c%s "$OUT/system.img") bytes"

step "Done"
find "$OUT" -maxdepth 1 -name '*.img' -printf '    %f  %s bytes\n'
