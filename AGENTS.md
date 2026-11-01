# エージェント向け作業ルール

このリポジトリで作業する AI エージェント（Claude、Codex など）向けのルールです。開発環境とビルドは [docs/development.md](docs/development.md)、リリースは [docs/release.md](docs/release.md) を見てください。

## ブランチの使い方

- `main` はいつでも動く状態に保つ。テスト（`npm --prefix web_scripts run check`、`flutter analyze lib test`、`flutter test`）が通らない変更は main に入れない。
- 作業は1タスクにつきブランチ1本。main から切り、テストが通ったらその日のうちに main へマージして、ブランチと worktree を削除する（ローカルとリモートの両方）。
- ブランチの上にブランチを作らない。続きの作業は、前のブランチを main にマージしてから main から新しく切る。
- 並行セッションがないときに存在するブランチは、`main` と作業中の1本だけにする。並行セッションはそれぞれ別のブランチと worktree が必要（git は1つのブランチを2か所に同時にチェックアウトできない）。その場合も各ブランチは終わり次第マージして消す。
- 他のセッションと同じチェックアウトを共有しているときは、関係ないブランチにコミットしない。push する前に `git log origin/<branch>..HEAD` で、自分のコミットだけが乗っているか確認する。
- push、PR のマージ、リモートブランチの削除は、ユーザーの許可を得てから行う。

## GitHub

- `gh` の既定リポジトリは upstream（koji-genba）になっている。このフォークを操作するときは `--repo terudoru/gakujo-chan-extender` を付ける。
