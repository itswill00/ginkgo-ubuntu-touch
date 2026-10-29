# Flashing guide

> **Device**: Xiaomi Redmi Note 8 (`ginkgo`, Snapdragon 665 / SM6125)
> **Target**: Ubuntu Touch 20.04 (Focal Fossa) on Halium 10
>
> Bahasa Indonesia: [FLASHING_GUIDE_id.md](FLASHING_GUIDE_id.md)

Read [Before you start](#before-you-start) before touching anything. The first
section is the part that decides whether you can recover from a mistake.

---

## Before you start

### What you need

| Item | Notes |
| --- | --- |
| Unlocked bootloader | Xiaomi requires the Mi Unlock tool and a 7-day wait on a fresh account |
| Custom recovery | TWRP or OrangeFox, with `adb` and a working terminal |
| The installer zip | from [Releases](https://github.com/itswill00/ginkgo-ubuntu-touch/releases) |
| A backup | the installer overwrites `system`; `/data` survives unless you ask for it to be formatted |

### Read this first

**ginkgo is A-only.** There is no `_a`/`_b` slot pair, so there is no second copy
of the system to fall back to. If the flash fails halfway, the device boots
nothing until you reflash stock with Mi Flash or fastboot. Have the stock firmware
for your exact model and region downloaded **before** you start.

`ginkgo` is the Redmi Note 8; `willow` is the 8T. They share a kernel and most of
the device tree, and the installer accepts both, but the vendor blobs differ. If
you are on an 8T, expect to need your own vendor image.

**This port has not been verified on hardware.** It builds and packages
correctly, but no one has booted it yet. Treat the first boot as an experiment.

---

## 1. Boot into recovery

Power off completely. Hold **Volume Down + Power** to reach fastboot, then:

```bash
fastboot boot twrp-ginkgo.img
```

Booting the recovery image rather than flashing it keeps your existing recovery
intact, which matters if you need it again.

---

## 2. Check that /data is ext4 and unencrypted

Ubuntu Touch keeps its rootfs on `/data/ubuntu`. Halium's initramfs mounts that
partition directly, so it must be **ext4** and **not** metadata-encrypted. Stock
HyperOS formats userdata as F2FS with file-based encryption, which will not mount.

From the recovery terminal:

```bash
blkid /dev/block/by-name/userdata
```

If the output says `f2fs` or mentions `metadata_csum_seed`, or if you are coming
from a stock ROM, you need to format. The installer does this for you when asked:

```bash
# in the recovery, after pushing the zip
adb push ginkgo-ut20.04-halium10-*.zip /tmp/
adb shell 'echo "--format-data" > /tmp/installer-args'
```

Or simply flash the zip once without `--format-data`, see whether it boots, and
re-flash with `--format-data` if it does not. Nothing is lost by trying, because
the installer leaves `/data` alone by default.

> Formatting erases everything on the device, including internal storage. Back up
> photos and anything else you care about first.

---

## 3. Flash the installer

```bash
adb push ginkgo-ut20.04-halium10-*.zip /tmp/
```

In the recovery: **Install** → select the zip → swipe to confirm.

The installer runs these steps and prints each one:

1. checks that the device really is `ginkgo` or `willow`
2. backs up `boot`, `dtbo` and `vbmeta` to `/sdcard/.ginkgo-backup-<timestamp>/`
3. clears the AVB and dm-verity flags in `vbmeta`
4. writes `boot.img`, `dtbo.img` and `system.img`
5. prepares `/data` if `--format-data` was given
6. writes the installed build details to `/sdcard/ginkgo-installed.txt`

If it stops with an error, read the message rather than re-running it. Each abort
names what failed, and step 3 in particular is fatal by design: without the AVB
flags cleared the bootloader will refuse to boot the new kernel.

---

## 4. First boot

Reboot to system. The first boot takes several minutes: the rootfs is unpacked and
the Android container is set up. Expect the Ubuntu Touch boot splash for a while
before the setup wizard appears.

Setup asks for language, region and a passcode. The default user is `phablet`;
`sudo` has no password.

---

## 5. Check what actually works

Run these from a terminal on the device. They are the checks that distinguish
"it booted" from "it works".

```bash
# which kernel is running
uname -a

# the Android container came up
systemctl status lxc-android-config

# binder is present, which everything on the Android side needs
ls -l /dev/binder /dev/hwbinder /dev/vndbinder

# the overlay was applied - this file only exists in the overlay
ls -l /opt/halium-overlay/vendor/etc/init/vndservicemanager.rc

# device-hacks ran
journalctl -u device-hacks --no-pager | tail -20

# modem
ofonoctl list

# panel backlight
cat /sys/class/backlight/panel0-backlight/brightness

# torch node
ls -l /sys/class/leds/led:torch_0/brightness
```

### What each result means

| Symptom | Likely cause |
| --- | --- |
| Stuck on the boot splash, no `lxc-android-config` | `/data` is not ext4, or the overlay did not mount |
| Boots, but no touch | `dtbo` was not written, or the panel DTB does not match your variant |
| No modem, `ofonoctl` empty | RIL subscription config or the vendor partition |
| `vndservicemanager.rc` missing | the overlay did not mount; check `mount-halium-overlay` |
| Fingerprint service missing | same, plus the fingerprint HAL init file |

Full detail: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Going back to Android

The installer backs up the stock `boot`, `dtbo` and `vbmeta` before replacing them.
To restore:

```bash
adb shell ls /sdcard/.ginkgo-backup-*/
```

Then in fastboot:

```bash
fastboot flash boot   boot.img
fastboot flash dtbo   dtbo.img
fastboot flash vbmeta vbmeta.img
```

`system` is not backed up — it is far too large to copy to `/sdcard` — so
restoring Android means reflashing a stock `system.img`, or the whole firmware
with Mi Flash. This is why the stock firmware should be downloaded first.

If you only want to wipe Ubuntu Touch and keep Android, formatting `/data` from
the recovery is enough.
