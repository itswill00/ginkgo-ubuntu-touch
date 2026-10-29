# Troubleshooting

Read the section matching your symptom. Every one of these starts with the same
question: how far did boot get? If you cannot answer that, start with
[Reading the boot log](#reading-the-boot-log).

---

## Reading the boot log

Most failures are visible before the splash screen goes away. There are three ways
to see the log, in order of usefulness.

### Over serial

The kernel command line sets `console=ttyMSM0,115200n8`. With a USB-to-serial
adapter on the test points you get the full kernel and init log. This is the only
method that shows output from the very first instruction.

### Through the recovery

If the device gets far enough to bring up USB, and the Android container starts,
`adb` becomes available. This does not help for failures before the container.

### On the next boot, from the previous one

systemd keeps the previous boot's journal:

```bash
journalctl -b -1 --no-pager
```

This is the most useful one in practice. If a boot fails and the device reboots
on its own, the journal of that failed boot is still there.

---

## Stuck on the splash screen

The device shows the Ubuntu Touch splash and never reaches the wizard.

### Check 1: is /data ext4 and unencrypted?

This is the most common cause, and the most common mistake. Halium's initramfs
mounts `/data` directly. F2FS, or ext4 with metadata encryption, will not mount.

From the recovery:

```bash
blkid /dev/block/by-name/userdata
```

Anything other than plain ext4 means you need to format. Re-flash the installer
with `--format-data`.

### Check 2: did the overlay mount?

The overlay is what makes the Android side usable. If it did not mount, the
container starts but nothing useful happens.

From a shell on the device (or `adb` if it comes up):

```bash
systemctl status mount-halium-overlay
ls /opt/halium-overlay/
```

If `/opt/halium-overlay` is empty or missing, the overlay was not installed into
the system image. That is a packaging problem, not a device problem — check that
`build-images.sh` copied `overlay/` before building.

### Check 3: is the kernel the one you built?

```bash
uname -a
```

Expect `4.14.190`. If it says something else, `boot.img` was not written, or was
written to the wrong partition. Check the installer output.

---

## Boots, but the screen does not respond

The display works but touch does nothing.

`dtbo.img` carries the device-specific device tree overlay, including the
touchscreen configuration. If it was not written, or the overlay does not match
your panel variant, touch will not initialise.

```bash
# is the touchscreen device present at all?
ls /dev/input/
dmesg | grep -i -E "touch|synaptics|novatek|focaltech"
```

ginkgo shipped with more than one touchscreen vendor across production runs. The
DTB in this repository is the one the upstream port uses; if your unit has a
different panel, the overlay needs to be regenerated for it.

---

## No modem

`ofonoctl list` returns nothing, or the modem never registers.

Two things to check, in this order:

```bash
# is the RIL config in place?
cat /etc/ofono/ril_subscription.d/ginkgo.conf

# did the RIL binder service start?
journalctl -b --no-pager | grep -i -E "ril|ofono" | tail -40
```

The port ships `ril_subscription.d/ginkgo.conf` with `SetRadioCapability=off`,
which is required on this modem. If the file is missing, the overlay did not
mount.

If the file is present but no service starts, the vendor partition is the likely
problem. The RIL blobs live there and are not part of this package.

---

## Fingerprint service missing

```bash
ls -l /vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc
```

That file is in the overlay at
`/opt/halium-overlay/vendor/etc/init/`. If it is missing from `/vendor`, the
overlay did not mount.

This is worth calling out because it was silently broken in the tree this port is
based on: the file was shipped under `/usr/share/halium-overlay`, which the rootfs
never reads because it probes `/opt/halium-overlay` first. See
[CHANGELOG.md](../CHANGELOG.md).

---

## The installer aborts

Each abort names its cause. The common ones:

| Message | Meaning |
| --- | --- |
| `wrong device` | `ro.product.device` is not ginkgo/willow. Check you have the right zip. `--force` overrides. |
| `cannot read vbmeta` | The vbmeta partition was not found or not readable. |
| `cannot write vbmeta` | The partition is read-only and `blockdev --setrw` did not help. |
| `boot.img is larger than the boot partition` | The image does not match this device. |
| `image directory not found in the package` | The zip is corrupt or was repacked incorrectly. |

If the installer aborts at the vbmeta step, **do not reboot into the system**.
That step is what allows an unsigned kernel to boot; without it the device will
refuse. Restore the backup it made, or reflash stock `vbmeta.img`.

---

## Recovering a device that will not boot

ginkgo is A-only, so there is no second slot to fall back to.

From fastboot:

```bash
# restore the images the installer backed up
fastboot flash boot   boot.img
fastboot flash dtbo   dtbo.img
fastboot flash vbmeta vbmeta.img
```

If the backup is not available, or `system` was overwritten and you want Android
back, you need the stock firmware for your exact model and region. Flash it with
Mi Flash, or extract the images and use fastboot.

`system` is never backed up by the installer — it is far too large to copy to
`/sdcard`. This is why the flashing guide tells you to download the firmware
first.

---

## Collecting a useful bug report

If you are going to open an issue, these four outputs answer most of the questions
before they are asked:

```bash
uname -a
cat /sdcard/ginkgo-installed.txt
journalctl -b --no-pager | tail -200
systemctl --failed --no-pager
```

Include the installer's console output too, if the problem is at flash time.
