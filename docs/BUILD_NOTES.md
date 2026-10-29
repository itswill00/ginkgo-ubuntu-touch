# Build notes

Notes on the parts of the build that are not obvious, and the two problems that had to be solved to
build this device at all on the available hardware.

## Host architecture

The build host is **aarch64**. That is not the architecture `halium-generic-adaptation-build-tools`
expects: its `build-kernel.sh` uses the AOSP prebuilt clang, which ships only as an `x86_64` binary.
On an aarch64 host that binary cannot execute, and the build fails at the first compile.

The kernel's own `Makefile` supports clang cross-compilation properly — it derives `--target` from
`CLANG_TRIPLE` — so the distribution clang works, and `scripts/build-kernel-native.sh` uses it
directly instead of going through `build-kernel.sh`.

```
CC=clang-14
LD=ld.lld
CLANG_TRIPLE=aarch64-linux-gnu-
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_ARM32=arm-linux-gnueabi-
```

### The 32-bit toolchain problem

`ginkgo-perf_defconfig` sets `CONFIG_COMPAT_VDSO=y`, so the kernel also builds a 32-bit vDSO for
AArch32 processes. That part must be assembled as ARM32, which means a second toolchain.

`arch/arm64/Makefile` builds the flag for it like this:

```make
export GCC_TOOLCHAIN32_DIR := $(dir $(shell which $(CROSS_COMPILE_ARM32)ld))
export CLANG_PREFIX32 := --prefix=$(GCC_TOOLCHAIN32_DIR)
```

`GCC_TOOLCHAIN32_DIR` is a **directory** (`/usr/bin/`), not a tool prefix. Passing it to
`--prefix=` makes clang look for an assembler literally named `as` in that directory, which resolves
to the host `aarch64-linux-gnu-as`. The result:

```
Assembler messages:
Error: unrecognized option -mfloat-abi=soft
clang: error: assembler command failed with exit code 1
```

The main `Makefile` gets this right for the 64-bit toolchain — it appends
`$(notdir $(CROSS_COMPILE))` to the directory. `arch/arm64/Makefile` omits the equivalent for the
32-bit one. `build-patches/0001-arm64-fix-clang-arm32-vdso-toolchain-prefix.patch` adds it:

```make
export CLANG_PREFIX32 := --prefix=$(GCC_TOOLCHAIN32_DIR)$(notdir $(CROSS_COMPILE_ARM32))
```

This is an upstream kernel bug, not a porting quirk; it only shows up when cross-compiling with
clang and a non-Android GCC toolchain.

## Why the kernel is not the vendor tree

Xiaomi publishes `ginkgo-q-oss` on MiCode, and that would be the obvious base. It is not used here
because it is the MIUI baseline: it does not carry the Halium-side changes this port needs.

The tree used instead is a Qualcomm CAF NICOBAR baseline
(`clo-LA.UM.9.11.c25-02800-NICOBAR.QSSI12c25.0`, 4.14.190) maintained for Halium. Its defconfig
already has, verified against the generated `.config`:

| Requirement | Setting |
| --- | --- |
| AppArmor (required by lomiri/UT) | `CONFIG_SECURITY_APPARMOR=y`, `CONFIG_DEFAULT_SECURITY_APPARMOR=y` |
| Binder for the Android container | `CONFIG_ANDROID_BINDER_IPC=y`, devices `binder,hwbinder,vndbinder` |
| Containers | `CONFIG_USER_NS`, `CONFIG_PID_NS`, `CONFIG_NET_NS`, `CONFIG_SECCOMP_FILTER` |
| Waydroid | `CONFIG_VETH`, `CONFIG_BRIDGE`, `CONFIG_OVERLAY_FS`, `CONFIG_FUSE_FS` |
| Android storage | `CONFIG_ASHMEM`, `CONFIG_ANDROID=y` |
| Debuggability | `CONFIG_IKCONFIG=y`, `CONFIG_IKCONFIG_PROC=y` |

SELinux is disabled and AppArmor is the default LSM, which is what Ubuntu Touch expects.

`schedtune` is absent from this kernel. `device-hacks` writes to
`/sys/fs/cgroup/schedtune/schedtune.boost` behind an `if [ -e ... ]` guard, so its absence is not
fatal — the boost simply does not happen.

## Rootfs selection

`deviceinfo_ubuntu_touch_release="focal"`. The adaptation tools accept `focal` as a value and map it
to:

- rootfs: `ubuntu-touch-android9plus-rootfs-arm64.tar.gz` from the `ubports/focal` CI job
- OTA channel: `20.04/arm64/android9plus/devel`

The OTA channel value matters less than it looks. `ginkgo` is **not** listed in
`20.04/arm64/android9plus/*` on system-image — UBports only ever published this device under
`16.04/arm64/android9` — so OTA updates against a ginkgo channel would 404 regardless. The system
image is built from the focal rootfs artifact and is self-contained.

## Build stages

| Stage | Command | Rough time |
| --- | --- | --- |
| kernel | `scripts/build-kernel-native.sh` | 25–40 min on 8 cores |
| device tarball | `build-tools/build.sh -b workdir` | ~1 min |
| rootfs + system image | `build-tools/prepare-fake-ota.sh` + `system-image-from-ota.sh` | 5–10 min |
| installer zip | `scripts/build_zip_local.sh` | <1 min |

The kernel is by far the slowest stage, and it is cached: `SKIP_KERNEL=1` reuses
`build-workspace/KERNEL_OBJ` if it already has `Image` and `Image.gz`.
