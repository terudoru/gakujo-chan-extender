# GitHub公開メモ

このディレクトリは、独立したFlutterアプリとして切り出したリポジトリです。
ローカルでは、参照用の読み取り専用リモートとして `upstream` を残しています。

```sh
https://github.com/yangniao23/gakujo-chan-extender.git
```

現在の公開先は次のリポジトリです。

```sh
https://github.com/terudoru/gakujo-chan-extender.git
```

公開先は、Android版アプリの内容を持つ `main` ブランチをdefault branchにしています。
フォーク元由来の古い `master` ブランチは削除済みです。

`upstream` リモートにはpushしないでください。誤って書き込まないように、
ローカルではpush URLを `DISABLED` にしています。

## 公開時の注意

このFlutter版は、元のブラウザ拡張機能リポジトリとは履歴を共有していません。
そのため、ブラウザ拡張機能側の履歴に対して通常のPull Requestを作る用途には
向いていません。

このリポジトリでは、Android版アプリとして独立公開し、上流への敬意と由来は
`NOTICE.md` に記載する方針です。

## コミットしないローカルファイル

次のファイルはgit管理外にしてください。

- `android/key.properties`
- `android/upload-keystore.jks`
- `android/local.properties`
- Flutter、Gradle、IDE、QAのビルド出力
