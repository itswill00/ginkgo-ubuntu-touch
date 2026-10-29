#!/bin/bash
# Build the ginkgo Halium 10 kernel natively.
#
# Why this exists: halium-generic-adaptation-build-tools assumes the host can run
# the x86_64 Android prebuilt clang from AOSP. On an aarch64 host that binary
# cannot execute, and the build dies at the first CC. This script uses the
# distribution clang instead, which cross-compiles fine because the kernel's
# Makefile derives --target from CLANG_TRIPLE.
#
# The 32-bit ARM toolchain is a separate problem: CONFIG_COMPAT_VDSO=y means the
# compat vDSO must be assembled as ARM32, and arch/arm64/Makefile builds
# --prefix= from GCC_TOOLCHAIN32_DIR, which is a directory rather than a tool
# prefix. Clang then resolves the assembler to /usr/bin/as (the host aarch64
# one) and fails with "unrecognized option -mfloat-abi=soft". build-patches/
# carries the one-line fix.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"

KERNEL_SRC="${KERNEL_SRC:-$REPO/build-workspace/kernel}"
OUT="${OUT:-$REPO/build-workspace/KERNEL_OBJ}"
JOBS="${JOBS:-$(nproc)}"
CC="${CC:-clang-14}"
LD="${LD:-ld.lld}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-arm-linux-gnueabi-}"
DEFCONFIG="${DEFCONFIG:-vendor/ginkgo-perf_defconfig}"

die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "Checking toolchain"
command -v "$CC" >/dev/null || die "$CC not found (apt install clang-14)"
command -v "$LD" >/dev/null || die "$LD not found (apt install lld-14)"
command -v "${CROSS_COMPILE}gcc" >/dev/null || die "${CROSS_COMPILE}gcc not found (apt install gcc-aarch64-linux-gnu)"
command -v "${CROSS_COMPILE_ARM32}as" >/dev/null || die "${CROSS_COMPILE_ARM32}as not found (apt install gcc-arm-linux-gnueabi)"
[ -d "$KERNEL_SRC" ] || die "kernel source missing at $KERNEL_SRC (set KERNEL_SRC)"

step "Applying build patches"
for patch in "$REPO"/build-patches/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch")"
    if git -C "$KERNEL_SRC" apply --reverse --check "$patch" 2>/dev/null; then
        echo "    already applied: $name"
    elif git -C "$KERNEL_SRC" apply --check "$patch" 2>/dev/null; then
        git -C "$KERNEL_SRC" apply "$patch"
        echo "    applied: $name"
    else
        die "cannot apply $name (kernel tree does not match expected baseline)"
    fi
done

mkdir -p "$OUT"

step "Configuring ($DEFCONFIG)"
make -C "$KERNEL_SRC" O="$OUT" ARCH=arm64 \
    CC="$CC" LD="$LD" \
    CLANG_TRIPLE="$CROSS_COMPILE" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    "$DEFCONFIG"

step "Building with $JOBS jobs"
make -C "$KERNEL_SRC" O="$OUT" ARCH=arm64 \
    CC="$CC" LD="$LD" \
    CLANG_TRIPLE="$CROSS_COMPILE" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    -j"$JOBS"

step "Verifying outputs"
for f in Image Image.gz; do
    [ -s "$OUT/arch/arm64/boot/$f" ] || die "missing $OUT/arch/arm64/boot/$f"
    printf '    %-28s %s bytes\n' "$f" "$(stat -c%s "$OUT/arch/arm64/boot/$f")"
done

echo
echo "Kernel version: $(make -s -C "$KERNEL_SRC" O="$OUT" kernelversion 2>/dev/null || echo unknown)"
echo "Output: $OUT"
