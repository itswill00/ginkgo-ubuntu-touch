#!/bin/bash
# End-to-end build for the ginkgo Ubuntu Touch port.
#
# Stages, each skippable:
#   kernel  - clone and build the kernel natively (scripts/build-kernel-native.sh)
#   images  - device tarball, then rootfs + system.img (UBports adaptation tools)
#   zip     - assemble the recovery installer (scripts/build_zip_local.sh)
#
# Nothing outside this repository is referenced. WORKSPACE defaults to
# build-workspace/ inside the repo.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"

WORKSPACE="${WORKSPACE:-$REPO/build-workspace}"
KERNEL_SRC="${KERNEL_SRC:-$WORKSPACE/kernel}"
KERNEL_OBJ="${KERNEL_OBJ:-$WORKSPACE/KERNEL_OBJ}"
BUILD_TOOLS="${BUILD_TOOLS:-$WORKSPACE/build-tools}"
JOBS="${JOBS:-$(nproc)}"
OUT="${OUT:-$REPO/out}"

SKIP_KERNEL="${SKIP_KERNEL:-0}"
SKIP_IMAGES="${SKIP_IMAGES:-0}"
SKIP_ZIP="${SKIP_ZIP:-0}"

KERNEL_URL="https://gitlab.com/areyoudeveloper/ut_kernel_xiaomi_sm6125"
BUILD_TOOLS_URL="https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools"

die() { printf '\n\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# ---------------------------------------------------------------------------
step "Checking host tools"

missing=()
need=(git make "$CC" "${CC:-clang-14}" dtc bc bison flex cpio rsync zstd jq wget)
for t in "${need[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
command -v clang-14 >/dev/null 2>&1 || missing+=("clang-14")
command -v ld.lld  >/dev/null 2>&1 || missing+=("ld.lld")
command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || missing+=("gcc-aarch64-linux-gnu")
command -v arm-linux-gnueabi-as  >/dev/null 2>&1 || missing+=("gcc-arm-linux-gnueabi")
command -v img2simg >/dev/null 2>&1 || missing+=("android-sdk-libsparse-utils")

if [ "${#missing[@]}" -gt 0 ]; then
    printf '    missing: %s\n' "${missing[*]}" >&2
    die "install the packages above and re-run"
fi
note "ok"

mkdir -p "$WORKSPACE" "$OUT"
# shellcheck source=/dev/null
source "$REPO/deviceinfo"
# deviceinfo is a sourced shell fragment; shellcheck cannot see the assignments.
# shellcheck disable=SC2154
KERNEL_BRANCH="$deviceinfo_kernel_source_branch"

# ---------------------------------------------------------------------------
if [ "$SKIP_KERNEL" = "1" ]; then
    step "Skipping kernel build (SKIP_KERNEL=1)"
    if [ ! -s "$KERNEL_OBJ/arch/arm64/boot/Image" ] || [ ! -s "$KERNEL_OBJ/arch/arm64/boot/Image.gz" ]; then
        die "SKIP_KERNEL=1 but $KERNEL_OBJ has no previous Image/Image.gz"
    fi
    note "reusing $KERNEL_OBJ"
else
    step "Kernel"
    if [ ! -d "$KERNEL_SRC/.git" ]; then
        note "cloning $KERNEL_URL"
        git clone --depth=1 --single-branch \
            -b "$KERNEL_BRANCH" "$KERNEL_URL" "$KERNEL_SRC"
    else
        note "reusing existing clone at $KERNEL_SRC"
    fi
    KERNEL_SRC="$KERNEL_SRC" OUT="$KERNEL_OBJ" JOBS="$JOBS" \
        "$HERE/build-kernel-native.sh"
fi

# ---------------------------------------------------------------------------
if [ "$SKIP_IMAGES" = "1" ]; then
    step "Skipping image build (SKIP_IMAGES=1)"
else
    step "Adaptation build tools"
    if [ ! -d "$BUILD_TOOLS/.git" ]; then
        note "cloning $BUILD_TOOLS_URL"
        git clone --depth=1 "$BUILD_TOOLS_URL" "$BUILD_TOOLS"
    else
        note "reusing existing clone at $BUILD_TOOLS"
    fi

    # The tools read deviceinfo and the overlay from their own directory, and
    # expect the kernel under <workdir>/downloads/<basename of kernel source>.
    WORK="$WORKSPACE/tools-work"
    rm -rf "$WORK"
    mkdir -p "$WORK"
    cp "$REPO/deviceinfo" "$WORK/deviceinfo"
    cp -a "$REPO/overlay" "$WORK/overlay"
    cp "$BUILD_TOOLS"/*.sh "$WORK"/ 2>/dev/null || true
    mkdir -p "$WORK/build"
    cp -a "$BUILD_TOOLS"/. "$WORK/build/"

    step "Device tarball"
    # build.sh -k builds only the kernel stage, which we have already done; the
    # remaining stages need the kernel object tree in place.
    ( cd "$WORK" && KERNEL_OBJ="$KERNEL_OBJ" \
        ./build/build.sh -b "$WORKSPACE/workdir" ) 2>&1 | tail -20
    tarball="$(find "$WORKSPACE/workdir/tmp" -maxdepth 1 -name 'device_*.tar.xz' 2>/dev/null | head -1)"
    [ -n "$tarball" ] || die "device tarball not produced"
    note "tarball: $tarball"

    step "Rootfs and system image"
    ( cd "$WORK" && ./build/prepare-fake-ota.sh "$tarball" "$WORKSPACE/ota" ) 2>&1 | tail -20
    ( cd "$WORK" && ./build/system-image-from-ota.sh "$WORKSPACE/ota/ubuntu_command" "$OUT" ) 2>&1 | tail -20
fi

# ---------------------------------------------------------------------------
for f in boot.img system.img; do
    [ -s "$OUT/$f" ] || die "missing $OUT/$f"
done
note "boot.img    $(stat -c%s "$OUT/boot.img") bytes"
note "system.img  $(stat -c%s "$OUT/system.img") bytes"

if [ "$SKIP_ZIP" = "1" ]; then
    step "Skipping installer zip (SKIP_ZIP=1)"
else
    step "Installer zip"
    "$HERE/build_zip_local.sh"
fi

step "Done"
note "workspace : $WORKSPACE"
note "output    : $OUT"
find "$OUT" -maxdepth 1 -name '*.zip' -printf '    %p (%s bytes)\n' 2>/dev/null || true
