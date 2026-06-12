# Notices

This Flutter app is a portable replacement client for the More-Better-Gakujo
Gakujo 2FA autofill flow. This repository is prepared as a fork-derived project
from:

- `koji-genba/gakujo-chan-extender`
- `yangniao23/gakujo-chan-extender`

The original application lineage is licensed under the MIT License. The MIT
license text and upstream copyright notice are included in this repository's
`LICENSE.md`.

This Flutter app adds a Dart/WebView implementation of the required 2FA path,
including Gakujo URL allowlisting, secure local secret access, TOTP generation,
`input[name="ninshoCode"]` autofill, and Android download organization by
course folder.
