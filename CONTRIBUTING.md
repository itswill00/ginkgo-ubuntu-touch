# Contributing

This is a device port. Most of what can go wrong is not a matter of style, so the
rules below are about not breaking things that already work rather than about
formatting.

## Before you change anything

Read these, in this order:

1. [`docs/PORT_LANDSCAPE.md`](docs/PORT_LANDSCAPE.md) — what the other ports for
   this device are, and why this one exists
2. [`docs/BUILD_NOTES.md`](docs/BUILD_NOTES.md) — the two build problems that
   shape the tooling
3. [`CHANGELOG.md`](CHANGELOG.md) — every fix here came from something being
   silently wrong, and the entries explain what

## Rules that are not negotiable

**The overlay goes in exactly one place.** `overlay/system/opt/halium-overlay/`
and nowhere else. The focal rootfs probes for the overlay and stops at the first
match, and `/opt/halium-overlay` comes before `/usr/share/halium-overlay`, so a
second tree is dead weight that makes the working one ambiguous. `make overlay`
enforces this.

**Do not edit generated files by hand.** `modules.load`-style lists and the
device tarball are produced by the build. If a generated file is wrong, fix the
thing that generates it.

**udev rules must not contain duplicates.** udev is last-match-wins, so a
duplicate means the earlier rule is dead, and if the two disagree the file reads
as though both apply. `make check` fails on duplicates and on conflicting
duplicates.

**Kernel changes go in `build-patches/`, not in a vendored tree.** The kernel is
cloned at build time. A patch must apply cleanly to the unmodified upstream
branch named in `deviceinfo`; CI checks this by cloning and applying.

**Filenames must not have leading or trailing whitespace.** One did, and it cost
an evening: `default/ lsc-wrapper.d` meant `MIR_ANDROID_FORCE_HWC2=1` was
installed somewhere nothing reads.

## Adding a kernel patch

```bash
cd build-workspace/kernel
# make the change
git diff > ../../build-patches/00NN-short-description.patch
```

Number it after the existing patches, and explain in the commit message **why**
the change is needed — which compiler, which config, what the failure was. The
existing patches are the model: each one names the symptom, the cause and the
one-line fix.

## Testing

There is no automated hardware test. What can be checked without a device:

```bash
make check          # syntax, shellcheck, deviceinfo, overlay
./scripts/build-all.sh
```

What cannot: whether the kernel binds a given driver, whether touch works,
whether the modem registers. If you change something in those areas, say so in
the commit and in the pull request — "not tested on hardware" is a useful and
honest statement, and a claim you cannot support is worse than no claim.

## Commits

```
area: short imperative summary

Why the change is needed, what the failure was, and what you ruled out.
If an assumption turned out to be wrong, say which one.

Signed-off-by: Your Name <you@example.com>
```

Areas in use: `kernel`, `overlay`, `installer`, `scripts`, `docs`, `ci`, `repo`.

Commits are signed off (`git commit -s`) and GPG-signed.

## Pull requests

State what you changed, why, and how it was verified. The template asks for the
two things most often missing: the reason, and the evidence.
