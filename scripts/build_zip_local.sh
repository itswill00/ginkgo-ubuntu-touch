#!/bin/bash
# Assemble the recovery installer zip from the built images.
#
# Layout inside the zip:
#   META-INF/com/google/android/update-binary   installer (busybox ash)
#   META-INF/com/google/android/updater-script  required by recoveries, contents ignored
#   images/boot.img
#   images/system.img
#   images/dtbo.img
#   build-info.txt                              what this zip was built from
#
# The zip is named after the port version, the Halium version, the date and the
# commit, so an installed device can be traced back to a build.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
OUT="${OUT:-$REPO/out}"
DIST="${DIST:-$REPO/dist}"

die() { printf '\n\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

VERSION="$(cat "$REPO/VERSION" 2>/dev/null || echo "0.0.0")"
HALIUM="$(sed -n 's/^deviceinfo_halium_version="\(.*\)"/\1/p' "$REPO/deviceinfo")"
CODENAME="$(sed -n 's/^deviceinfo_codename="\(.*\)"/\1/p' "$REPO/deviceinfo")"
[ -n "$CODENAME" ] || die "cannot read deviceinfo_codename from deviceinfo"

step "Checking inputs"
for f in boot.img system.img; do
    [ -s "$OUT/$f" ] || die "missing $OUT/$f"
done
[ -s "$OUT/dtbo.img" ] || die "missing $OUT/dtbo.img"
printf '    %-12s %s bytes\n' boot.img   "$(stat -c%s "$OUT/boot.img")"
printf '    %-12s %s bytes\n' system.img "$(stat -c%s "$OUT/system.img")"
printf '    %-12s %s bytes\n' dtbo.img   "$(stat -c%s "$OUT/dtbo.img")"

# A dirty tree must be visible in the artifact name: otherwise the zip claims to
# be built from a commit it does not match.
COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
    DIRTY="-dirty"
else
    DIRTY=""
fi
DATE="$(date -u +%Y%m%d)"
NAME="tanzanite-ut20.04-halium${HALIUM}-v${VERSION}-${DATE}-${COMMIT}${DIRTY}.zip"
NAME="ginkgo-ut20.04-halium${HALIUM}-v${VERSION}-${DATE}-${COMMIT}${DIRTY}.zip"

step "Staging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/images"

cp "$REPO/flashable_zips/update-binary.template.sh" "$STAGE/META-INF/com/google/android/update-binary"
chmod 755 "$STAGE/META-INF/com/google/android/update-binary"
printf '# dummy, recovery requires the file to exist\n' \
    > "$STAGE/META-INF/com/google/android/updater-script"

cp "$OUT/boot.img"   "$STAGE/images/boot.img"
cp "$OUT/system.img" "$STAGE/images/system.img"
cp "$OUT/dtbo.img"   "$STAGE/images/dtbo.img"

{
    echo "device=$CODENAME"
    echo "version=$VERSION"
    echo "halium=$HALIUM"
    echo "ubuntu_touch=20.04"
    echo "commit=$COMMIT"
    echo "dirty=${DIRTY:-no}"
    echo "built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "boot_sha256=$(sha256sum "$OUT/boot.img"   | cut -d' ' -f1)"
    echo "system_sha256=$(sha256sum "$OUT/system.img" | cut -d' ' -f1)"
    echo "dtbo_sha256=$(sha256sum "$OUT/dtbo.img"   | cut -d' ' -f1)"
} > "$STAGE/build-info.txt"

step "Compressing"
mkdir -p "$DIST"
rm -f "$DIST/$NAME"
# system.img is mostly zeros; store it, compression gains little and costs time.
( cd "$STAGE" && zip -r -9 -q "$DIST/$NAME" . )

step "Checksums"
( cd "$DIST" && sha256sum "$NAME" > "$NAME.sha256" )
cp "$STAGE/build-info.txt" "$DIST/$NAME.buildinfo"

step "Done"
printf '    %s\n' "$DIST/$NAME"
printf '    %s bytes\n' "$(stat -c%s "$DIST/$NAME")"
printf '    %s\n' "$(cat "$DIST/$NAME.sha256")"
