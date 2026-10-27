# 通知事項

このAndroidアプリは、独立したFlutterリポジトリとして公開しています。

このアプリは More-Better-Gakujo / Gakujo-chan-extender 系のアイデアを参考にし、
Android WebView向けに実装したものです。

主な上流プロジェクト:

- https://github.com/koji-genba/gakujo-chan-extender

関連するフォーク:

- https://github.com/yangniao23/gakujo-chan-extender

上流のブラウザ拡張機能のREADMEには、元の作者が2024年4月1日以降は
メンテナンスできない旨が記載されています。そのため、このAndroidアプリは
公式の上流リリースではなく、Android WebViewで使うための非公式な独立継続版
として扱ってください。

このアプリは、新潟大学および元のブラウザ拡張機能の作者と関係ありません。

同梱しているサードパーティのコード:

- `third_party/webview_flutter_windows`: webview_flutter_windows 1.2.0
  （BSD 3-Clause、https://github.com/omar-hanafy/webview_flutter_windows）。
  タッチパッドのスクロール処理を修正しています。ライセンスは同ディレクトリの
  `LICENSE` を参照してください。
- `assets/js/upload_compression/`: 添付ファイル圧縮に使う pdf.js 3.11.174
  （Apache-2.0、Mozilla）、pdf-lib 1.17.1（MIT）、JSZip 3.10.1（MIT）。
  qpdf 12.4.2 の WebAssembly 版（Apache-2.0、Emscripten 4.0.14 でビルド）は
  zlib 1.3.1 と IJG libjpeg 9f を含みます。This software is based in part on the work
  of the Independent JPEG Group.
  pdf.js の動的な字形評価を無効化し、worker の注釈、フォント対応表、
  シェーディング解析に処理量の上限と診断転送を追加しています。
  IJG 9f の README は `LICENSE.libjpeg-9f`、その他のライセンスは
  同ディレクトリの `LICENSE.*` を参照してください。
