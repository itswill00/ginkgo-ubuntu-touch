# Changelog

All notable changes to this port. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-29

First build. **Not verified on hardware** — see the note at the end of this entry.

### Added

- Halium 10 device tree for `ginkgo`, targeting Ubuntu Touch 20.04 (focal)
- Kernel build path that works on an aarch64 host, where the AOSP prebuilt
  clang cannot run
- Recovery installer for an A-only device: writes `boot`, `dtbo` and `system`,
  handles AVB and dm-verity, backs up what it replaces
- Post-flash checks and a troubleshooting guide
- CI that validates shell syntax, shellcheck, deviceinfo parsing, udev rules and
  overlay consistency

### Fixed

Six defects were found in the tree this port is based on. All are upstream, not
introduced here.

**The fingerprint HAL and vendor binder services were never started.**
The overlay shipped two halium-overlay trees at once, `/opt/halium-overlay` and
`/usr/share/halium-overlay`. The focal rootfs resolves the overlay by probing a
fixed list and stopping at the first hit, and `/opt` comes first, so the four
files under `/usr/share/halium-overlay` were never read:
`android.hardware.biometrics.fingerprint@2.1-service.rc`,
`vndservicemanager.rc`, `vendor/bin/time_daemon` and `system/etc/prop.halium`.
The first two are load-bearing — one starts the fingerprint service, the other is
required for vendor binder services on Android 10. Everything now lives under
`/opt/halium-overlay`.

**HWC2 fallback was never enabled.** `overlay/system/etc/default/ lsc-wrapper.d`
had a leading space in its directory name, so `MIR_ANDROID_FORCE_HWC2=1` was
installed to a path nothing reads.

**`repowerd.service` was malformed.** It declared `[Service]` twice. systemd takes
the first section and rejects the duplicate, so the unit could not be loaded and
the `ExecStartPre` sleep that keeps repowerd from racing the Android container was
never applied.

**Two udev rule files shadowed each other.** `70-willow.rules` and
`70-ginkgo.rules` shipped rules for the same devices with different owners, and
udev applies both in lexical order, so the effective permissions depended on
filename sort order. `70-willow.rules` was removed. Nine duplicate rules inside
the surviving file were also dropped; udev is last-match-wins, so the earlier
copies were dead, and two of them (`hw_random`, `rtc0`) disagreed with the rule
that actually won.

**A filename had a trailing space.** `android.hardware.biometrics.fingerprint@2.1-service.rc `
would have been installed under a name init never looks for.

**Three upstart jobs could not run on focal.** `apply-halium-overlay.conf`,
`ipa_fws.conf` and `halium-overlay.sh` are upstart, and focal is systemd-only.
The first is replaced by `mount-halium-overlay.service` in the rootfs, and the
second's WLAN enable is already done by `device-hacks`, which does run.

### Build fixes

The kernel needed four patches to compile with a modern clang. Details and
reasoning are in [`build-patches/`](build-patches/) and
[`docs/BUILD_NOTES.md`](docs/BUILD_NOTES.md).

- `arch/arm64/Makefile` passed a directory to clang's `--prefix`, so the ARM32
  compat vDSO was assembled by the host aarch64 assembler and failed on
  `-mfloat-abi=soft`
- `unused-but-set-variable` was only disabled for GCC, not clang, while 229 hits
  in vendor code are compiled with `-Werror`
- 24 `techpack/audio` Kbuild files computed include paths from `$(shell pwd)`,
  which is the output directory under `O=`, so no techpack header resolved
- Two drivers discarded a return value: `q6audio_v2_aio.c` ignored a metadata
  extraction failure and posted a read-done event anyway, `max98937.c` ignored a
  calibration read failure and stored whatever impedance was left over

### Known issues

- **Not verified on hardware.** The kernel builds, the images are produced and the
  package is assembled, but nothing here has been booted. Whether each subsystem
  binds is unknown until it is flashed.
- `schedtune` is absent from this kernel, so the boost in `device-hacks` is a
  no-op. The write is guarded by an existence check.
- `ginkgo` is not present in any 20.04 or 24.04 system-image channel, so OTA
  updates are not available. The system image is built from the focal rootfs
  artifact and is self-contained.
