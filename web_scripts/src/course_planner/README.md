# 学務から履修プランナーに取り込む

アプリの「メニュー」→「履修プランナー」で専用 WebView が開きます。大学のシラバス詳細から開いた場合は、公開されている年度と開講番号で科目を指定します。

アプリ内の計画は専用 WebView に保存されます。従来のメニューから外部ブラウザーに保存した計画は、引き続きそのブラウザーで開けます。

学務にログインして「成績」→「単位修得状況照会」、または「履修」→「履修登録・登録状況照会」を表示し、「メニュー」→「学務の照会結果をプランナーに取り込む」を選びます。取り込む項目を選ぶと専用 WebView が開きます。プランナー上で対象を確認して保存します。区分別の既修得単位数は、その区分と既修得単位の列が画面に表示された場合に取り込めます。帳票 PDF だけに表がある場合は、プランナーのファイル取り込みを使います。

履修手帖に渡すときは「学務の照会結果を履修手帖用にコピー」で項目を選び、「単位・要件」に貼り付けます。「所属・学年（候補）」は学務の照会画面で「所属」と「学年」が隣接セルに表示される場合に読み取れます。所属だけが表示されている場合は学年を空欄にします。

時間割内の開講番号と許可表示、および「不許可となった科目」の別表を照合します。時間割のコマの背景色は開講形態を示します。学務への申請・確定は学務で本人が行います。[大学の履修登録手順書 9 ページ](https://www.niigata-u.ac.jp/wp-content/uploads/2020/03/risyuu_tejun.pdf#page=9)・[学務情報システム留学生向けマニュアル 6 ページ](https://www.niigata-u.ac.jp/wp-content/uploads/2025/03/J_studentweb_manual.pdf#page=7)

## ローカルで動かす

リポジトリのルートで `npm --prefix web_scripts ci` と `npm --prefix web_scripts run build` を実行します。続いて `npm --prefix course_planner ci`、`npm --prefix course_planner run dev` を実行します。別のターミナルで Vite が表示したループバック URL を指定して起動します。

```sh
flutter run -d windows --dart-define=MBG_COURSE_PLANNER_URL=http://127.0.0.1:5173/
```

学務 WebView では、表示中の公式フレームとログインの世代を照会から受け渡しまで確認します。専用 WebView ではロードしたページの origin・パス・Document を照合します。受信側は `window` に `mbg:planner-import` と `mbg:planner-probe` のリスナーを登録してから `mbg:planner-ready` を発行し、各 probe に対しても同期的に同じ ready を返します。ネイティブ側は同じ取り込み操作につき一度だけ、許可した表を `CustomEvent.detail` で渡します。アカウントや画面が変わった場合は学務画面からやり直します。

## 合成データでの検証

```sh
npm --prefix web_scripts run check
node test/support/course_planner_portal_browser.mjs
flutter test test/course_planner_native_route_test.dart test/course_planner_link_test.dart
powershell -File test/support/course_planner_windows_smoke.ps1
```

ブラウザー検証は Chrome の一時プロファイルでリクエストを合成 HTML に差し替えます。Windows 用の最後のコマンドは `build/course_planner_smoke_host/` に独立した検証アプリを作り、新しい WebView2 プロファイルで実際のプランナー表示経路を開きます。ループバックの確認画面に合成した科目名が表示されると、同ホストの実行ごとのディレクトリに `result.txt` を残します。
