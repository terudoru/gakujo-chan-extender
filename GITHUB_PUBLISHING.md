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

GitHub Releases の配布ファイル名は、利用者が迷わないように
`MoreBetterGakujo-vX.Y.Z.<拡張子>` の形に揃えます。タグ push だけで別の
workflow が同じ Release に asset を追加しないよう、Release 作成 workflow は
手動実行に限定しています。

## GitHub ActionsでのWindows配布物作成

`Release Windows Installer` workflow を手動実行すると、指定したタグから
Windows版だけをビルドして GitHub Releases に添付します。

- `MoreBetterGakujo-vX.Y.Z.zip`
- `MoreBetterGakujo-vX.Y.Z.exe`

実行手順:

1. GitHub の Actions タブで `Release Windows Installer` を開く
2. `Run workflow` を選ぶ
3. `tag_name` に `v0.67.0` のようなタグ名を入力する
4. 完了後、同じタグの Release assets を確認する

Windows の `.zip` はポータブル版、`.exe` は Inno Setup で作成する
インストーラーです。Android/iOS/macOS の配布物はこの workflow では作成しません。

## コミットしないローカルファイル

次のファイルはgit管理外にしてください。

- `android/key.properties`
- `android/upload-keystore.jks`
- `android/local.properties`
- Flutter、Gradle、IDE、QAのビルド出力
