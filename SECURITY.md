# Security policy

## What this project is

A build recipe and installer for running Ubuntu Touch on a Xiaomi Redmi Note 8.
It is not a distribution and it does not maintain packages; it assembles a system
image from UBports' focal rootfs and a kernel built from a public source tree.

## Reporting

Open a private security advisory on this repository, or email the address in the
git commits. Do not open a public issue for anything that could be exploited
before a fix exists.

There is no bug bounty and no response-time guarantee. This is a hobby port with
one maintainer.

## Threat model

This is the part worth reading, because a phone OS port makes trade-offs that are
not obvious and some of them are deliberate.

### What this port does not protect against

**The bootloader is unlocked.** Unlocking it is a prerequisite, and it means
anyone with physical access can flash a different kernel or system image. Physical
access is game over, by design.

**AVB and dm-verity are disabled.** The installer clears the verification flags in
`vbmeta` (big-endian `0x00000003` at offset 120). This is not optional: the kernel
and system image are not signed by Xiaomi, so the bootloader would refuse to boot
them otherwise. The consequence is that the boot chain is no longer verified — a
modified `boot` or `system` partition will boot without complaint.

**`/data` is unencrypted ext4.** Halium's initramfs mounts `/data` directly, and
file-based encryption as Android implements it is not available to the Ubuntu side.
Anything on the device is readable by anyone who can mount the partition. If you
lose the phone, treat its contents as disclosed.

**There is no verified boot after the first stage.** Combined with the above, an
attacker who can write to the partitions can persist across reboots in ways that
are not detectable from inside the running system.

### What it does protect against

**Remote attackers are not privileged by default.** Ubuntu Touch runs AppArmor as
the default LSM (confirmed in the kernel config as `CONFIG_DEFAULT_SECURITY_APPARMOR`),
and applications are confined. The Android container's SELinux is disabled, which
is normal for Halium but does mean the Android side is less confined than on stock.

**The installer does not trust its inputs blindly.** It verifies the device
codename, checks that each image fits its target partition before writing, and
aborts rather than continuing when the vbmeta flags cannot be written. Aborting
matters: a device with a replaced kernel and intact verification flags does not
boot at all.

**Nothing is downloaded and executed unverified at install time.** The package is
self-contained. The build downloads a rootfs and a kernel source tree, and the
build is reproducible from the committed `deviceinfo` and patches, but the
installer itself does not fetch anything.

### Supply chain

| Component | Source | Verified how |
| --- | --- | --- |
| Kernel source | `areyoudeveloper/ut_kernel_xiaomi_sm6125` on GitLab | pinned to a branch, patches checked in CI |
| Rootfs | UBports CI, `ubports/focal` | fetched over HTTPS, pinned to the artifact URL |
| Android container image | UBports generic system image | fetched over HTTPS |
| Build tools | UBports adaptation tools, LineageOS mkbootimg, AOSP avb/libufdt | fetched over HTTPS at build time |

The build is not bit-for-bit reproducible: the rootfs and the Android container
image are moving CI artifacts, so two builds on different days produce different
images. The installer records the build it came from in `build-info.txt` and
`/sdcard/ginkgo-installed.txt` so an installed system can be traced back.

### Known weak points

- The installer runs as root in recovery with no signature check on the zip
  itself. A recovery that will flash an unsigned zip will flash a modified one.
- The backup the installer writes to `/sdcard` includes `vbmeta` and `boot` but
  not `system`, which is too large. A modified `system` cannot be detected by
  comparing against a backup.
- `ro.debuggable` and the ADB configuration come from the rootfs, not from this
  repository.

## Supported versions

Only the latest release. This is a port, not a supported product; older releases
are not patched.
