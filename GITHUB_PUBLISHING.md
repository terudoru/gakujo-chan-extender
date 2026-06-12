# GitHub Publishing Notes

This directory is a standalone Flutter extraction with its own initial git
history. It keeps `upstream` as a read-only reference to:

```sh
https://github.com/yangniao23/gakujo-chan-extender.git
```

Before publishing, create or choose the GitHub repository that should receive
this Flutter-only app, then set `origin` locally:

```sh
git remote add origin git@github.com:<your-user-or-org>/<repo>.git
git push -u origin main
```

If `<repo>` is a GitHub fork that already contains upstream extension history,
this Flutter-only repository will not share that history. In that case, either:

- publish this as a new standalone repository and mention the upstream lineage
  in `NOTICE.md`, or
- intentionally replace a branch in the fork after reviewing the consequences.

Do not push the `upstream` remote. Its push URL is set to `DISABLED` locally to
avoid accidental writes.

Local files intentionally ignored and not committed:

- `android/key.properties`
- `android/upload-keystore.jks`
- `android/local.properties`
- Flutter, Gradle, IDE, and QA build outputs
