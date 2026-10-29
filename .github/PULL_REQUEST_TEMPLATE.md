## What this changes

<!-- One or two sentences. If it fixes a symptom, name the symptom and the mechanism. -->

## Why

<!--
The diff says what. This section says why it is needed and what you ruled out.
If an assumption turned out to be wrong, say which one — several entries in
CHANGELOG.md exist because that was written down properly.
-->

## How it was verified

- [ ] `make check` passes (syntax, shellcheck, deviceinfo, overlay consistency)
- [ ] If it touches the overlay: the file is under `opt/halium-overlay/`, not `usr/share/`
- [ ] If it touches udev rules: no duplicate or conflicting `(ACTION, KERNEL)` pairs
- [ ] If it adds a kernel patch: it applies cleanly to the unmodified upstream branch
- [ ] If it touches the installer: reviewed the recovery-time behaviour by hand
- [ ] Tested on device (say what you saw, or say "not tested on hardware")

## Affected area

<!-- kernel / overlay / installer / scripts / docs / ci -->

## Checklist

- [ ] Commit messages explain why, not just what
- [ ] Commits are signed off (`git commit -s`)
- [ ] No build products, images or zips included
- [ ] Documentation updated if behaviour changed

## Related

<!-- Issue numbers, upstream commits, firmware versions -->
