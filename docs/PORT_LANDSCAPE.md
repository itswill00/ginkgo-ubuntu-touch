# The ginkgo port landscape

Four Ubuntu Touch device trees exist for the Redmi Note 8 / 8T. This document records what each one
is, what state it is in, and why this repository is a fifth rather than a fork of any of them.

All four target the same hardware. `ginkgo` is the Redmi Note 8, `willow` is the 8T; they share a
SoC, kernel and most of the device tree, and the trees are frequently named for one while covering
both.

## The four existing ports

### 1. `ubports/porting/community-ports/android9/xiaomi-redmi-note-8t/xiaomi-ginkgo-willow`

The only one hosted by UBports itself. Halium 9, kernel 4.14.

- Last functional commit: **2022-04-19** (an Apache-2.0 license commit landed in 2026)
- CI: `16.04/arm64/android9/devel`
- `ginkgo` **is** present in `16.04/arm64/android9` on system-image, so this port can be installed
  with the UBports installer

The problem is the target. Ubuntu Touch 16.04 (xenial) is end of life. Its apt archives are gone, so
a device running it cannot be updated, and the security posture is that of a 2019 image. It is the
most "official" port for this device and the least usable one.

It is also the reason `ginkgo` does not appear in any 20.04 or 24.04 channel: the port was never
migrated, so the device was never registered there.

### 2. `i0i0i-i0i0i/xiaomi-ginkgo-ut`

Halium 10, targeting 24.04 with `ubuntu-touch-android9plus-rootfs-arm64`.

- Overlay is the most complete of the four: apparmor tunables, NetworkManager AP fix, gstreamer
  overrides, fingerprint service rc, time_daemon, repowerd config
- CI: **every pipeline failing** as of its last activity (2026-07-26), five consecutive failures
- No README, so the failures are not documented

The overlay is worth reading even though the tree does not build. Several files here originate from
it.

### 3. `areyoudeveloper/xiaomi-ginkgo-willow`

Halium 10, targeting 24.04.

- Last commit: `Initial noble adaptation` (2026-01-16)
- CI: **success**, including a `devel-flashable` job that produced `boot.img` and `system.img`
  artifacts
- Kernel: `areyoudeveloper/ut_kernel_xiaomi_sm6125`, branch
  `clo-LA.UM.9.11.c25-02800-NICOBAR.QSSI12c25.0`, still active (last commit 2026-03-02)

This is the healthiest tree and the one this repository is based on. Its deviceinfo, overlay and
kernel source are carried over; the changes are the ones listed in the commit log — a retarget to
focal, and four overlay defects (a directory name with a leading space, a malformed repowerd unit,
two udev rule files that shadowed each other, and nine dead rules inside the surviving one).

### 4. `0312birdzhang/xiaomi-ginkgo-willow`

A fork of (3). Pipeline success in 2025-11, no changes of note beyond the base.

## Why not fork (3) directly?

Because the differences are not additive. Retargeting the rootfs from 24.04 to 20.04 changes
`deviceinfo`, the rootfs source, the OTA channel and the expected cgroup version, and the overlay
carries fixes that only make sense as a documented set. A fork would have preserved the original
`deviceinfo` and made the deltas invisible. Recording them as commits against a fresh tree keeps the
reasoning attached to the change.

## What is genuinely different here

| | (1) UBports | (2) i0i0i | (3) areyoudeveloper | this repo |
| --- | --- | --- | --- | --- |
| Halium | 9 | 10 | 10 | **10** |
| Rootfs | 16.04 xenial (EOL) | 24.04 | 24.04 | **20.04 focal** |
| CI state | builds | failing | passing | passing |
| Installer | UBports installer | none | manual | **recovery zip** |
| Builds on aarch64 host | no | no | no | **yes** |

The last row is not a boast: the ARM32 vDSO patch in `build-patches/` is what makes a native
cross-compile possible, and none of the other three carry it. They rely on the x86_64 AOSP prebuilt
clang.

## Credit

The device tree, overlay and kernel used here are other people's work. The port would not exist
without `areyoudeveloper`'s Halium 10 tree and kernel, and several overlay files trace back further
to the original UBports port and to `i0i0i`'s 24.04 attempt. What this repository adds is the focal
retarget, the overlay fixes, the aarch64 build path and the installer.
