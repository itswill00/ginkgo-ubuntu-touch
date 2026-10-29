# Panduan flashing

> **Perangkat**: Xiaomi Redmi Note 8 (`ginkgo`, Snapdragon 665 / SM6125)
> **Target**: Ubuntu Touch 20.04 (Focal Fossa) di atas Halium 10
>
> English: [FLASHING_GUIDE_en.md](FLASHING_GUIDE_en.md)

Baca [Sebelum mulai](#sebelum-mulai) dulu. Bagian itu yang menentukan apakah lo
bisa balik kalau ada yang salah.

---

## Sebelum mulai

### Yang dibutuhkan

| Item | Keterangan |
| --- | --- |
| Bootloader unlocked | Xiaomi pakai Mi Unlock, akun baru kena tunggu 7 hari |
| Custom recovery | TWRP atau OrangeFox, harus ada `adb` dan terminal |
| Zip installer | dari [Releases](https://github.com/itswill00/ginkgo-ubuntu-touch/releases) |
| Backup | installer menimpa `system`; `/data` aman kecuali lo minta diformat |

### Baca ini dulu

**ginkgo itu A-only.** Gak ada pasangan slot `_a`/`_b`, jadi gak ada salinan
sistem kedua buat fallback. Kalau flashing gagal di tengah, HP gak bisa boot apa
pun sampai lo flash ulang stock pakai Mi Flash atau fastboot. **Download firmware
stock yang persis sesuai model dan region lo sebelum mulai.**

`ginkgo` itu Redmi Note 8, `willow` itu 8T. Kernel dan sebagian besar device tree
sama, dan installer menerima keduanya, tapi blob vendor-nya beda. Kalau lo pakai
8T, siap-siap butuh vendor image sendiri.

**Port ini belum diverifikasi di hardware.** Build dan packaging-nya benar, tapi
belum ada yang booting. Anggap boot pertama sebagai eksperimen.

---

## 1. Masuk recovery

Matikan total. Tahan **Volume Down + Power** sampai masuk fastboot, lalu:

```bash
fastboot boot twrp-ginkgo.img
```

Boot image recovery-nya, jangan di-flash. Recovery lo yang sekarang tetap utuh
kalau nanti masih dibutuhkan.

---

## 2. Pastikan /data sudah ext4 dan tidak terenkripsi

Ubuntu Touch naruh rootfs-nya di `/data/ubuntu`. Initramfs Halium mount partisi
itu langsung, jadi harus **ext4** dan **tidak** metadata-encrypted. HyperOS stock
memformat userdata sebagai F2FS dengan file-based encryption — itu gak akan bisa
di-mount.

Dari terminal recovery:

```bash
blkid /dev/block/by-name/userdata
```

Kalau hasilnya `f2fs`, atau menyebut `metadata_csum_seed`, atau lo datang dari ROM
stock, lo perlu format. Installer bisa melakukannya kalau diminta:

```bash
adb push ginkgo-ut20.04-halium10-*.zip /tmp/
adb shell 'echo "--format-data" > /tmp/installer-args'
```

Atau flash zip-nya dulu tanpa `--format-data`, lihat apakah boot, lalu flash ulang
dengan `--format-data` kalau gagal. Gak ada yang hilang dengan mencoba, karena
installer default-nya **tidak** menyentuh `/data`.

> Format menghapus semua isi perangkat, termasuk internal storage. Backup foto dan
> data lain dulu.

---

## 3. Flash installer

```bash
adb push ginkgo-ut20.04-halium10-*.zip /tmp/
```

Di recovery: **Install** → pilih zip → swipe.

Installer menjalankan langkah berikut dan mencetak masing-masing:

1. memastikan perangkat benar-benar `ginkgo` atau `willow`
2. backup `boot`, `dtbo`, dan `vbmeta` ke `/sdcard/.ginkgo-backup-<timestamp>/`
3. menghapus flag AVB dan dm-verity di `vbmeta`
4. menulis `boot.img`, `dtbo.img`, dan `system.img`
5. menyiapkan `/data` kalau `--format-data` diberikan
6. mencatat detail build ke `/sdcard/ginkgo-installed.txt`

Kalau berhenti dengan error, baca pesannya — jangan langsung ulang. Tiap abort
menyebut apa yang gagal, dan langkah 3 memang fatal by design: tanpa flag AVB
dibersihkan, bootloader akan menolak boot kernel baru.

---

## 4. Boot pertama

Reboot ke system. Boot pertama butuh beberapa menit: rootfs diekstrak dan
container Android disiapkan. Bakal lama di splash Ubuntu Touch sebelum wizard
setup muncul.

Setup nanya bahasa, region, dan passcode. User default `phablet`; `sudo` tanpa
password.

---

## 5. Cek apa yang benar-benar jalan

Jalankan dari terminal di perangkat. Ini yang membedakan "booting" dari "jalan".

```bash
uname -a
systemctl status lxc-android-config
ls -l /dev/binder /dev/hwbinder /dev/vndbinder
ls -l /opt/halium-overlay/vendor/etc/init/vndservicemanager.rc
journalctl -u device-hacks --no-pager | tail -20
ofonoctl list
cat /sys/class/backlight/panel0-backlight/brightness
ls -l /sys/class/leds/led:torch_0/brightness
```

### Arti tiap hasil

| Gejala | Kemungkinan penyebab |
| --- | --- |
| Nyangkut di splash, `lxc-android-config` gak ada | `/data` bukan ext4, atau overlay gagal mount |
| Booting, tapi layar gak responsif | `dtbo` belum tertulis, atau DTB panel gak cocok varian lo |
| Gak ada modem, `ofonoctl` kosong | config RIL subscription atau partisi vendor |
| `vndservicemanager.rc` hilang | overlay gagal mount; cek `mount-halium-overlay` |
| Service fingerprint gak ada | sama, plus file init HAL fingerprint |

Detail lengkap: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Balik ke Android

Installer mem-backup `boot`, `dtbo`, dan `vbmeta` stock sebelum diganti. Buat
restore:

```bash
adb shell ls /sdcard/.ginkgo-backup-*/
```

Lalu di fastboot:

```bash
fastboot flash boot   boot.img
fastboot flash dtbo   dtbo.img
fastboot flash vbmeta vbmeta.img
```

`system` **tidak** di-backup — terlalu besar buat disalin ke `/sdcard` — jadi
buat balik ke Android lo harus flash `system.img` stock, atau seluruh firmware
pakai Mi Flash. Ini alasan firmware stock harus diunduh duluan.

Kalau cuma mau hapus Ubuntu Touch dan tetap pakai Android, format `/data` dari
recovery sudah cukup.
