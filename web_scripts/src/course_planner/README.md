# 学務から履修手帖に取り込む

アプリの縦三点「メニュー」→「履修手帖を開く」で `https://gakujo.terudoru.com/syllabus/` を外部ブラウザーで開きます。

学務にログインして「成績」→「単位修得状況照会」、または「履修」→「履修登録・登録状況照会」を表示し、「メニュー」→「学務の照会結果をプランナーに取り込む」または「学務の照会結果を履修手帖用にコピー」を選びます。項目を選んで個人情報のコピーを確認すると、MBGPLAN1 形式でクリップボードにコピーします。表示される「履修手帖を開く」からブラウザーに移り、設定 →「More Better Gakujo から貼り付け」で内容を確認して取り込みます。

区分別の既修得単位数は、その区分と既修得単位の列が画面に表示された場合に取り込めます。帳票 PDF だけに表がある場合は、履修手帖のファイル取り込みを使います。「所属・学年（候補）」は学務の照会画面で「所属」と「学年」が隣接セルに表示される場合に読み取れます。所属だけが表示されている場合は学年を空欄にします。

時間割内の開講番号と許可表示、および「不許可となった科目」の別表を照合します。時間割のコマの背景色は開講形態を示します。学務への申請・確定は学務で本人が行います。[大学の履修登録手順書 9 ページ](https://www.niigata-u.ac.jp/wp-content/uploads/2020/03/risyuu_tejun.pdf#page=9)・[学務情報システム留学生向けマニュアル 6 ページ](https://www.niigata-u.ac.jp/wp-content/uploads/2025/03/J_studentweb_manual.pdf#page=7)

照会データの取得では、表示中の公式フレームとログインの世代を確認します。アカウントや画面が変わった場合は学務画面からやり直します。MBG は履修手帖を WebView に埋め込まず、学務の認証情報をブラウザーに渡しません。

## 合成データでの検証

リポジトリのルートで依存関係を準備して実行します。

```sh
npm --prefix web_scripts ci
npm --prefix course_planner ci
npm --prefix web_scripts run check
node test/support/course_planner_portal_browser.mjs
flutter test test/course_planner_handoff_test.dart test/gakujo_toolbar_copy_url_test.dart
```

ブラウザー検証は Chrome の一時プロファイルでリクエストを合成 HTML に差し替えます。ウィジェット検証は外部ブラウザーのランチャーをモックし、URL と外部起動設定を確認します。
