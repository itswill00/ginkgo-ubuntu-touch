# Release notes archive

One file per release, written at release time and committed so the reasoning
behind a release is versioned with the code that implements it. The same text is
used as the GitHub release body.

| Version | Date | Summary | Notes |
| --- | --- | --- | --- |
| 0.1.0 | 2026-10-29 | First build; six upstream overlay defects and four kernel patches | [v0.1.0.md](v0.1.0.md) |

## Naming

```
ginkgo-ut20.04-halium10-v0.1.0-20261029-6eaaff3.zip
│      │       │         │      │        └─ commit the artifact was built from
│      │       │         │      └────────── build date, UTC
│      │       │         └───────────────── port version, from VERSION
│      │       └─────────────────────────── Halium version
│      └─────────────────────────────────── Ubuntu Touch rootfs release
└────────────────────────────────────────── device codename
```

A `-dirty` suffix is appended when the tree the artifact was built from had
uncommitted changes. Only release artifacts are built from a clean tree, so a
`-dirty` zip is by definition not a release.

## Verifying a download

```bash
git verify-tag v0.1.0
sha256sum -c ginkgo-ut20.04-halium10-v0.1.0-*.zip.sha256
```

Tags are GPG-signed by the same identity as the commit author.
