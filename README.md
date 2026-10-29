# Ubuntu Touch 20.04 for Redmi Note 8 (`ginkgo`)

<p align="center">
  <a href="https://github.com/itswill00/ginkgo-ubuntu-touch/releases/latest"><img src="https://img.shields.io/github/v/release/itswill00/ginkgo-ubuntu-touch?style=flat-square&label=release&color=77216F" alt="Latest release"></a>
  <a href="https://github.com/itswill00/ginkgo-ubuntu-touch/actions/workflows/validate.yml"><img src="https://img.shields.io/github/actions/workflow/status/itswill00/ginkgo-ubuntu-touch/validate.yml?branch=main&style=flat-square&label=validate" alt="Validation status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/itswill00/ginkgo-ubuntu-touch?style=flat-square&color=blue" alt="License"></a>
  <img src="https://img.shields.io/badge/Ubuntu%20Touch-20.04-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu Touch 20.04">
  <img src="https://img.shields.io/badge/Halium-10-4E9A06?style=flat-square" alt="Halium 10">
  <img src="https://img.shields.io/badge/device-Redmi%20Note%208-FF6900?style=flat-square&logo=xiaomi&logoColor=white" alt="Redmi Note 8">
  <img src="https://img.shields.io/badge/SoC-SM6125-8E44AD?style=flat-square" alt="SM6125">
  <img src="https://img.shields.io/badge/kernel-4.14%20CAF-333333?style=flat-square&logo=linux&logoColor=white" alt="Kernel 4.14 CAF">
</p>

<p align="center">
  <a href="https://github.com/itswill00/ginkgo-ubuntu-touch/commits/main"><img src="https://img.shields.io/github/last-commit/itswill00/ginkgo-ubuntu-touch?style=flat-square&label=last%20commit" alt="Last commit"></a>
  <a href="https://github.com/itswill00/ginkgo-ubuntu-touch/stargazers"><img src="https://img.shields.io/github/stars/itswill00/ginkgo-ubuntu-touch?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/itswill00/ginkgo-ubuntu-touch/issues"><img src="https://img.shields.io/github/issues/itswill00/ginkgo-ubuntu-touch?style=flat-square" alt="Issues"></a>
  <a href="https://github.com/itswill00/ginkgo-ubuntu-touch/releases"><img src="https://img.shields.io/github/downloads/itswill00/ginkgo-ubuntu-touch/total?style=flat-square&label=downloads" alt="Downloads"></a>
</p>

Build recipe, overlay and recovery installer for **Ubuntu Touch 20.04 (Focal Fossa) / Halium 10**
on the **Xiaomi Redmi Note 8** (`ginkgo`, Qualcomm Snapdragon 665 / SM6125).

> **Status: built, not yet verified on hardware.** The kernel compiles, the images are produced and
> the module lists are consistent. Whether each subsystem actually binds on the device can only be
> confirmed by flashing it. See [Verification](#verification) for what to check.

---

## Why this device is different from a MediaTek port

The Redmi Note 8 is a Qualcomm device from 2019, and that changes almost everything about the work:

| | MediaTek GKI device | ginkgo (this port) |
| --- | --- | --- |
| Kernel source | withheld by vendor | **published** — `ginkgo-q-oss` on MiCode |
| Kernel version | 5.10 GKI | 4.14.190 CAF NICOBAR |
| Partitions | dynamic (`super`), A/B | **A-only, real `system` partition** |
| Vendor modules | separate `vendor_dlkm` image | inside `vendor`, shipped in the rootfs |
| AVB | `vbmeta` with flags | `vbmeta` present, `dm-verity` on system |
| Installer | resize `super`, repack vendor | plain `system` + `boot` write |

Concretely: there is no dynamic partition resize, no slot suffix, no `vendor_dlkm` recovery step. The
installer writes `system` and `boot` and stops. Most of the complexity that a GKI port carries
simply does not exist here.

---

## Repository layout

```
deviceinfo                     Halium build configuration (the authoritative source of truth)
overlay/system/                files installed into the UT rootfs
  etc/deviceinfo/devices/      hardware description consumed by lomiri-system-settings
  etc/ofono/                   RIL subscription config for the dual-SIM modem
  lib/udev/rules.d/            device node permissions
  usr/libexec/lxc-android-config/device-hacks   post-boot fixups
  usr/share/repowerd/          auto-brightness curve
build-patches/                 kernel patches, applied by the build script
scripts/                       build, check and packaging helpers
flashable_zips/                recovery installer source
docs/                          reasoning, decisions and post-flash checks
```

## Building

### Requirements

An **aarch64** or x86_64 Linux host. The kernel build does not use the AOSP prebuilt clang — see
[`docs/BUILD_NOTES.md`](docs/BUILD_NOTES.md) for why, and for the ARM32 toolchain issue that
`build-patches/` fixes.

```bash
sudo apt install clang-14 lld-14 llvm-14 gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
                 bc bison flex libssl-dev libelf-dev cpio kmod rsync zstd jq \
                 android-sdk-libsparse-utils
```

### One command

```bash
./scripts/build-all.sh
```

This clones the kernel and the UBports adaptation tools if absent, applies `build-patches/`, builds
the kernel, produces the device tarball, fetches the focal rootfs and assembles the installer zip.
`SKIP_KERNEL=1`, `SKIP_IMAGES=1` and `SKIP_ZIP=1` reuse or skip stages.

## Installing

Download from [Releases](https://github.com/itswill00/ginkgo-ubuntu-touch/releases/latest).
Release notes and the reasoning behind each build are archived in
[`docs/releases/`](docs/releases/README.md).

See [`docs/FLASHING_GUIDE_en.md`](docs/FLASHING_GUIDE_en.md) (English) or
[`docs/FLASHING_GUIDE_id.md`](docs/FLASHING_GUIDE_id.md) (Bahasa Indonesia).

Short version, from a recovery with working `adb`:

1. Back up everything. The installer overwrites `system`.
2. Flash the installer zip. It writes `system` and `boot`, and leaves `/data` alone unless you ask
   it to format.
3. Reboot. First boot takes several minutes.

## Verification

After the first boot, these are the checks that matter:

```bash
# kernel actually booted, and which one
uname -a

# the Android container came up
systemctl status lxc-android-config

# binder devices exist
ls -l /dev/binder /dev/hwbinder /dev/vndbinder

# modem registered
ofonoctl list

# panel and touch
cat /sys/class/backlight/panel0-backlight/brightness
```

If the device does not boot at all, [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) walks
through reading the boot log and checking the three things that usually break first.

## Differences from the upstream ports

Three ports for this device exist, and this repository is a fourth. The differences are deliberate
and documented in [`docs/PORT_LANDSCAPE.md`](docs/PORT_LANDSCAPE.md):

| Port | Halium | Rootfs | State |
| --- | --- | --- | --- |
| `ubports/.../xiaomi-ginkgo-willow` | 9 | 16.04 xenial (EOL) | last commit 2022 |
| `i0i0i-i0i0i/xiaomi-ginkgo-ut` | 10 | 24.04 | all pipelines failing |
| `areyoudeveloper/xiaomi-ginkgo-willow` | 10 | 24.04 | builds, artifacts published |
| **this repository** | 10 | **20.04 focal** | see status above |

## License

Apache-2.0 for the contents of this repository. The kernel is GPL-2.0 and is not vendored here; it is
cloned at build time from its upstream.
