# 履修年度のシラバス照合

履修年度・開講所属・開講番号・科目名を当時の開講情報と照合する。入学年度や適用便覧の年度は検索条件に使わない。開講番号がない場合、同じ年度に同名の授業が複数あれば本人が選択する。経済学部・経済科学部の異名27組は読替候補に限り、本人の確認後に対応を保存する。[大学のシラバス検索](https://syllabus.niigata-u.ac.jp/campus-sy/)／[経済学部生向けの公式読替表](https://www.econ.niigata-u.ac.jp/topics/files/elfinder/gakumu/読替が可能な経済科学部授業科目一覧.pdf)

## 公開情報の収録範囲

2026年11月19日確認。件数は開講所属と開講番号の組の数。「分野あり」は公式情報に分野番号がある授業数。2016〜2025年度の49,291件は、照合する年度だけを端末に読み込む。1年度分はgzip圧縮で約48〜57 KiB。

| 履修年度 | 開講件数 | 分野あり | 確認した公式情報の例 |
| --- | ---: | ---: | --- |
| 2016 | 4,965 | 4,965 | [全学検索](https://syllabus.niigata-u.ac.jp/campus-sy/)で年度「2016」・開講番号「160G0001」を指定。個別ページの標本は404で、保存には本人の選択が必要 |
| 2017 | 5,659 | 5,659 | [共通英語・170G0233](https://syllabus.niigata-u.ac.jp/syllabusHtml/2017/84/84_170G0233_ja_JP.html) |
| 2018 | 5,367 | 5,367 | [共通英語・180G0233](https://syllabus.niigata-u.ac.jp/syllabusHtml/2018/84/84_180G0233_ja_JP.html) |
| 2019 | 5,124 | 5,119 | [共通英語・190G0233](https://syllabus.niigata-u.ac.jp/syllabusHtml/2019/84/84_190G0233_ja_JP.html) |
| 2020 | 4,809 | 4,809 | [実践コミュニケーション英語Ⅰ・200G0105](https://syllabus.niigata-u.ac.jp/syllabusHtml/2020/84/84_200G0105_ja_JP.html) |
| 2021 | 4,728 | 4,728 | [実践コミュニケーション英語Ⅰ・210G0002](https://syllabus.niigata-u.ac.jp/syllabusHtml/2021/84/84_210G0002_ja_JP.html) |
| 2022 | 4,707 | 4,707 | [実践コミュニケーション英語Ⅰ・220G0001](https://syllabus.niigata-u.ac.jp/syllabusHtml/2022/84/84_220G0001_ja_JP.html) |
| 2023 | 4,674 | 4,673 | [実践コミュニケーション英語Ⅰ・230G0001](https://syllabus.niigata-u.ac.jp/syllabusHtml/2023/84/84_230G0001_ja_JP.html) |
| 2024 | 4,634 | 4,634 | [実践コミュニケーション英語Ⅰ・240G0002](https://syllabus.niigata-u.ac.jp/syllabusHtml/2024/84/84_240G0002_ja_JP.html) |
| 2025 | 4,624 | 4,624 | [IELTS PreparationⅠ・250G0001](https://syllabus.niigata-u.ac.jp/syllabusHtml/2025/84/84_250G0001_ja_JP.html) |
| 2026 | 4,347 | 4,347 | [英語基礎 L・261G7011](https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/84/84_261G7011_ja_JP.html)／[エンジニアのためのデータサイエンス入門・261G3008](https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/84/84_261G3008_ja_JP.html) |

2016年度は443件で科目区分を取得できなかった。2019年度の5件と2023年度の1件は個別シラバスでも分野番号を確認できなかった。分野と科目区分は別々に保持し、記載のない項目は空欄にする。2019〜2025年度の「医歯学」の補完には、該当年度の授業科目開設一覧にある開講番号と表見出しを照合し、使用ページを各レコードに記録した。[2025年度授業科目開設一覧](https://www.iess.niigata-u.ac.jp/acpb/upload/20250327103752014129200.pdf)

歯学部の公開目次では1999・2000年度に各26科目、2001年度に21科目、2002年度に44科目、2003年度に60科目を確認した。これらは本人が選べる目次の科目名で、分野番号・開講番号は空欄。2004・2005年度の目次は冊子単位で、確認した個別PDFは404だった。全学索引がない年度でも、当時の公開シラバスを保存したHTMLか、該当授業を記載した大学公式PDFのページから本人が照合できる。PDFの転記内容は本人確認による。[歯学部の年度別シラバス目次](https://www.dent.niigata-u.ac.jp/student/syllabus/)

2026年度は公開検索と既存カタログの開講番号4,347件が一致した。印刷版由来の分野と公開検索の分野が異なる95件は、個別シラバスを開いて分野番号を確認した。和文ページがない19件は英文ページの年度と開講番号を照合した。[分野「28・30」の例](https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/01/01_260H2016_ja_JP.html)

## 呼び出し側での利用

- `packs.mjs` の `await matchHistoricalGrades(incomingGrades, catalog, previousGrades)` が各行の `matchedCourse` を返す。元の成績の科目名、単位、年度、開講番号は保持する。取り込みを確定するときに保存し、集計には照合済みの分野・科目区分を使う。同名の未解決行は別の成績として維持する。
- 各行の確認には `<HistoricalMatchPanel grade={originalGrade} catalog={catalog} onConfirm={saveMatch} />` を使う。`saveMatch(matchedCourse)` は対象の成績行だけを更新し、保存に失敗した場合は例外か `false` を返す。ユーザーが選んだ年度は `matchedCourse.year` に残る。
- 同期・再取り込み時は `matchedCourse` の `year, code, department, title, fields, category, sourceUrl, confirmed`、出典の `sourceKind, fieldSource, categorySource, aliasSource`、資料に記載がある `term, period, semester, section, courseId, credits, schedule` を保持する。成績の修得単位は引き続き `grade.credits` から集計する。
- 個別照合には `await loadHistoricalIndex(studyYear, catalog)` と `resolveHistoricalGrade(grade, index)` を使う。授業検索・予定の分野表示を成績と揃えるには、現行カタログの各行を `currentOffering(course, catalog)` に渡す。この関数の `sourceUrl` は参照可能な公式シラバスを指す。

### 学期・クラス・単位数の不一致

科目名や開講番号が一致しても、成績と資料の学期・クラス・科目番号・単位数が矛盾する候補は選択できない。成績にある値を資料で確かめられない場合は本人の照合を待つ。過年度索引には開講時期があっても単位数がない場合がある。本人が対応を確認しても、成績の値から資料の空欄を補わない。2026年度「情報通信技術教育論I」は第1ターム・1単位で、同名の第4ターム・3単位の成績は分野要確認に残る。[授業の公式シラバス](https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/03/03_261K0501_ja_JP.html)

ローカル保存・同期の既存成績は、集計前に `packs.mjs` の同期関数 `revalidateGradeMatch(grade, currentCatalog, historicalIndex?)` で保存済みの対応を確認する。戻り値は確認できた `matchedCourse` または `null`。該当年度の現行カタログ、または読み込み済みの過年度索引で、古い対応に欠けている根拠も確認する。オフラインで索引がない場合には、保存済みの根拠と矛盾しない既存の確認を維持する。集計用の成績コピーに戻り値を設定し、`null` の場合は分野と科目区分を空にする。この表示用処理による保存・同期は不要。

再取り込み時、`matchHistoricalGrades` が一意に対応した旧 `matchedCourse` を資料で反証できた場合だけ、対象行に `matchedCourse: null` と一時フラグ `matchInvalidated: true` を返す。対応が新たに見つからない場合や、年度パック取得に失敗しただけの場合はフラグを付けない。保存時は同じ成績IDの旧対応が読み取り時点と一致する場合だけ解除し、並行操作で本人が確認した別の対応を保持する。フラグは保存・同期しない。

## データ更新

`tools/archive_index.py CACHE YEAR ...` を `--dimension departments`、`fields`、`categories` で実行する。検索に使うのは公開の年度・開講所属・学問分野・科目細区分で、成績行を送信する処理はない。`tools/archive_pack.py CACHE YEAR ...` が各検索条件の結果を照合し、年度別JSONを生成する。

再取得時は、`archive_pack.py` の `LISTINGS` にある公式PDFを `tools/pdf-layout.cjs` で `YEAR-layout.json` に変換して `--layouts DIR` に渡す。2026年度の開講所属・分野検索後に `--current-sources` を実行すると公開シラバスの差分を更新できる。読替表は同じPDF変換後に `--aliases-layout FILE`、歯学部目次は `--dental` で更新できる。
