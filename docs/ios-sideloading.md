# iOS/iPadOS 自己署名配布

iOS/iPadOS 版は、通常のApp Store配布ではなく、技術者向けの自己署名配布として
扱います。

iOS/iPadOS 14 以降が必要です。

## 配布先を分ける

用途ごとに2つの導線を使います。

- Sideloadly: 自分用、またはMac/PCを持っていて常駐更新を管理できる人向け
- SideStore: Macを持っていないが、SideStoreの初期設定を自力で進められる技術者向け

どちらも同じ `.ipa` を使います。アプリの署名は、利用者それぞれのApple Accountで
行います。

## 配布ファイル

iOS/iPadOS版のIPAは、`Release All Platforms` workflow（`.github/workflows/release.yml`）が
タグ push 時に GitHub Actions 上で作成し、他プラットフォームの配布物と一緒に
GitHub Releases へアップロードします。ローカルでの手動作成は、検証や緊急時の
バックアップ手段として残しています。

配布ファイル名は次の形に揃えます。

```text
MoreBetterGakujo-v0.68.0.ipa
```

SideStore/AltStore source は、リポジトリ内の `distribution/altstore-source.json` を
raw URL で案内します。source内の `downloadURL` は、実際に配布するIPA
（GitHub Releases のアセットURL）に合わせます。

```text
https://raw.githubusercontent.com/terudoru/gakujo-chan-extender/main/distribution/altstore-source.json
```

アプリのBundle IDは固定します。

```text
net.yoshida.morebettergakujo
```

Bundle IDを変えると、Sideloadly/SideStoreからは別アプリとして扱われます。

## 自分用: Sideloadly

1. `MoreBetterGakujo-vX.Y.Z.ipa` を作ります。
2. Mac/PCでSideloadlyを開きます。
3. IPAをSideloadlyへドロップします。
4. 対象のiPhone/iPadを選びます。
5. 自分のApple Accountで署名します。
6. Sideloadlyの自動更新デーモンを有効にしておきます。

この導線は、PC、Apple Account、更新デーモンを自分で管理できる場合に向いています。

## Macなし技術者向け: SideStore

利用者には、次のどちらかを案内します。

- Source URLをSideStoreに追加して、More Better Gakujoをインストールする
- GitHub ReleasesからIPAを直接ダウンロードし、SideStoreで開く

推奨するSource URL:

```text
https://raw.githubusercontent.com/terudoru/gakujo-chan-extender/main/distribution/altstore-source.json
```

現在のsourceファイル:

```text
distribution/altstore-source.json
```

sourceの再生成は `Release All Platforms` workflow の publish ジョブが
リリース公開後に自動で行い、`main` ブランチへコミットします。手動で
リリースする場合だけ、実際に公開するIPAからsourceを再生成して、`size`、
`version`、`buildVersion`、リリースノートを合わせます。

## IPAを手動で作る

macOSにXcodeとFlutterが入っている環境で実行します。

```sh
./scripts/package_ios_ipa.sh
```

出力先:

```text
dist/MoreBetterGakujo-v0.68.0.ipa
```

このIPAはApp Store用の署名済みビルドではありません。SideloadlyやSideStore側で、
利用者が自分のApple Accountを使って署名します。

## SideStore sourceを手動で作る

IPAを作ったあとに実行します（通常はリリースworkflowが自動で行います）。

```sh
./scripts/generate_altstore_source.sh dist/MoreBetterGakujo-v0.68.0.ipa
```

任意の環境変数:

```sh
RELEASE_TAG=v0.66.0 \
RELEASE_NOTES="iOS sideloading build." \
./scripts/generate_altstore_source.sh dist/MoreBetterGakujo-v0.66.0.ipa
```

生成された `distribution/altstore-source.json` は、リリース前またはリリースと同時に
コミットします。

## GitHub Actionsでの扱い

`Release All Platforms` workflow が、タグ push（または手動実行）で
Android・iOS・macOS・Windows の配布物をすべて作成し、GitHub Releases へ
公開します。iOS/iPadOS版のIPA作成と SideStore source の更新もこの workflow に
含まれます。署名は行わず、未署名IPAを配布します（署名は利用者側で行います）。

## 利用者に明記する注意点

IPAを案内する場所には、次の点を明記します。

- iOS/iPadOS版は非公式ビルドです。
- 利用者は自分のApple Accountでアプリに署名します。
- 無料Apple Accountでは、通常7日以内に更新が必要です。
- 無料Apple Accountでは、同時に有効化できるサイドロードアプリ数に制限があります。
- Appleやサイドロードツールの仕様変更で、インストールや更新が壊れる可能性があります。
- Apple IDのパスワード、証明書、プロビジョニングプロファイルを他人と共有しないでください。
