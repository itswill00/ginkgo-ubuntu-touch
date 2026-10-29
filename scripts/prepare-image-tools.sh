#!/bin/bash
# Prepare the tools needed by the image stage, without the AOSP toolchains.
#
# halium-generic-adaptation-build-tools/build.sh runs setup_repositories.sh, which
# clones the x86_64 AOSP prebuilt clang and GCC and then builds the kernel with
# them. On an aarch64 host those binaries cannot execute, and the kernel has
# already been built natively by build-kernel-native.sh anyway.
#
# This script fetches only what the post-kernel stages need: mkbootimg, avbtool,
# libufdt, and the Halium boot ramdisk. Everything lands in $DOWN so that the
# stage scripts can be invoked with that directory as their first argument.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
DOWN="${DOWN:-$REPO/build-workspace/downloads}"

MKBOOTIMG_URL="https://github.com/LineageOS/android_system_tools_mkbootimg"
MKBOOTIMG_BRANCH="lineage-20.0"
AVB_URL="https://android.googlesource.com/platform/external/avb"
AVB_BRANCH="android13-gsi"
UFDT_URL="https://android.googlesource.com/platform/system/libufdt"
UFDT_BRANCH="pie-gsi"
RAMDISK_URL="https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

step "Preparing $DOWN"
mkdir -p "$DOWN"
cd "$DOWN"

step "mkbootimg"
if [ -d android_system_tools_mkbootimg/.git ]; then
    note "already present"
else
    git clone --depth=1 -b "$MKBOOTIMG_BRANCH" "$MKBOOTIMG_URL" android_system_tools_mkbootimg
fi
[ -f android_system_tools_mkbootimg/mkbootimg.py ] || {
    printf 'mkbootimg.py missing from the clone\n' >&2; exit 1; }
note "ok"

step "avbtool"
if [ -d avb/.git ]; then
    note "already present"
else
    git clone --depth=1 -b "$AVB_BRANCH" "$AVB_URL" avb
fi
[ -f avb/avbtool ] || { printf 'avbtool missing from the clone\n' >&2; exit 1; }
chmod +x avb/avbtool
note "ok"

step "libufdt"
if [ -d libufdt/.git ]; then
    note "already present"
else
    git clone --depth=1 -b "$UFDT_BRANCH" "$UFDT_URL" libufdt
fi
[ -f libufdt/utils/src/mkdtboimg.py ] || {
    printf 'mkdtboimg.py missing from the clone\n' >&2; exit 1; }

# mkdtboimg.py on pie-gsi is Python 2. Check whether it runs under python3 before
# deciding anything, because a newer revision of the file is Python 3 already.
if python3 libufdt/utils/src/mkdtboimg.py --help >/dev/null 2>&1; then
    note "mkdtboimg.py is python3-compatible"
    mkdir -p "$REPO/build-workspace/bin"
    printf '#!/bin/sh\nexec python3 %s/libufdt/utils/src/mkdtboimg.py "$@"\n' \
        "$DOWN" > "$REPO/build-workspace/bin/mkdtboimg"
    chmod +x "$REPO/build-workspace/bin/mkdtboimg"
    note "wrapper: build-workspace/bin/mkdtboimg"
else
    printf 'mkdtboimg.py is not python3-compatible; a python2 is required\n' >&2
    exit 1
fi

step "Halium boot ramdisk"
if [ -s halium-boot-ramdisk.img ]; then
    note "already present"
else
    curl -L --fail --output halium-boot-ramdisk.img "$RAMDISK_URL"
fi
note "$(stat -c%s halium-boot-ramdisk.img) bytes"

step "Done"
note "tools are in $DOWN"
