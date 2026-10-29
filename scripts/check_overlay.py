#!/usr/bin/env python3
"""Consistency checks for the overlay that shell alone makes awkward."""
import glob
import os
import re
import sys

failures = 0


def fail(msg):
    global failures
    failures += 1
    print(f"    {msg}")


def check_udev():
    """udev is last-match-wins, so a duplicate rule means the earlier one is dead.

    A duplicate that also disagrees about owner or mode is worse than dead: it
    means whoever wrote the second one was fixing a mistake in the first, and the
    file reads as if both are in effect.
    """
    print("==> udev rules")
    for path in sorted(glob.glob("overlay/**/udev/rules.d/*.rules", recursive=True)):
        seen = {}
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if not line.startswith("ACTION"):
                continue
            action = re.match(r'ACTION=="([^"]*)"', line)
            kernel = re.search(r'KERNEL=="([^"]*)"', line)
            if not (action and kernel):
                fail(f"{path}:{n}: rule without ACTION or KERNEL")
                continue
            key = (action.group(1), kernel.group(1))
            if key in seen:
                prev_n, prev_line = seen[key]
                if prev_line.split(",")[1:] == line.split(",")[1:]:
                    fail(f"{path}:{n}: duplicate rule for {key[1]} (also line {prev_n})")
                else:
                    fail(
                        f"{path}:{n}: conflicting rule for {key[1]} "
                        f"(line {prev_n} differs, and the later one silently wins)"
                    )
            seen[key] = (n, line)
    if not failures:
        print("    ok")


def check_overlay_location():
    """The focal rootfs probes for the overlay and stops at the first hit.

    /usr/libexec/lxc-android-config/mount-halium-overlay tries, in order:
        /android/system/halium, /android/system/ubuntu,
        /opt/halium-overlay/, /usr/share/halium-overlay/
    so a tree with both is not merely untidy - the second one is dead, and the
    adaptation tools refuse to build it anyway.
    """
    print("==> halium overlay location")
    found = sorted(glob.glob("overlay/**/halium-overlay", recursive=True))
    found = [p for p in found if p.endswith("halium-overlay")]
    if len(found) != 1:
        fail(f"found {len(found)} halium-overlay directories, expected exactly 1")
        for p in found:
            print(f"      {p}")
        return
    if "opt/halium-overlay" not in found[0]:
        fail(f"{found[0]} is not under /opt, which is the only path the rootfs reads")
        return
    print("    ok")


def check_no_trailing_space_names():
    """A trailing space in a filename survives tar and zip and is invisible."""
    print("==> filenames")
    for path in glob.glob("overlay/**/*", recursive=True):
        name = path.rsplit("/", 1)[-1]
        if name != name.rstrip():
            fail(f"{path!r}: trailing whitespace in filename")
    if not failures:
        print("    ok")


def check_overlay_payloads():
    """Overlay files bind-mounted into /android must be usable.

    A zero-length file is usually a packaging mistake, but one case is
    intentional: vendor/bin/time_daemon is deliberately empty, because
    init.qcom.usb.rc overrides the service as
    "service time_daemon vendor.time_daemon_HYBRIS_DISABLED" and device-hacks
    stops it. Shipping an empty file is how the daemon is neutralised. Files in
    that allowlist are expected to be empty; everything else must not be.
    """
    print("==> overlay payloads")
    intentionally_empty = {
        "overlay/system/opt/halium-overlay/vendor/bin/time_daemon",
    }
    for path in sorted(glob.glob("overlay/**/halium-overlay/**/*", recursive=True)):
        if not os.path.isfile(path):
            continue
        size = os.path.getsize(path)
        if size == 0 and path not in intentionally_empty:
            fail(f"{path}: zero-length file in the halium overlay")
        elif size > 0 and path in intentionally_empty:
            fail(
                f"{path}: expected to be empty (it disables a service), "
                f"but is {size} bytes"
            )
    if not failures:
        print("    ok")


for check in (check_udev, check_overlay_location, check_no_trailing_space_names,
              check_overlay_payloads):
    check()

print()
if failures:
    print(f"RESULT: {failures} problem(s) found")
    sys.exit(1)
print("RESULT: overlay is consistent")
