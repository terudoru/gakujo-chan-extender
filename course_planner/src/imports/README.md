# 学務帳票の取込

ファイルを選ぶと、該当する行・読み取った単位・確認が必要な理由を表示する。保存は利用者がチェックした行に限る。PDF のバイト列、ページ全文、ファイル名は保存しない。

## React への接続

`App` のルートで受信を開始する。手動でファイルを開くボタンは `setSource({ kind: "grades" })`、`"registration"` または `"balances"` を指定する。学務からの受信には同じパネルを使う。

```jsx
import { installPlannerImportListener } from "./imports/native.mjs";
import { PlannerImportPanel } from "./imports/PlannerImportPanel.jsx";

const [source, setSource] = useState(null);
useEffect(
  () =>
    installPlannerImportListener(
      (packet) => setSource({ packet }),
      (error) => setError(error.message),
    ),
  [],
);

// 現在選んでいる目標・段階の要件行と、当該段階に適用する分野別の行を渡す。
{
  source && (
    <PlannerImportPanel
      {...source}
      state={state}
      byCode={byCode}
      catalogYear={catalog.year}
      goal={goal}
      stage={stageId}
      requirementRows={currentStageRows}
      mutate={mutate}
      onClose={() => setSource(null)}
    />
  );
}
```

`mutate(update)` は最新の保存データを `update` に渡し、保存成功で `true` を返す。ファイルと学務の受信データは `reviewPlannerImport(packet, { byCode, catalogYear, grades, profile, goal, stage, requirementRows })` で同じ判定を通る。戻り値の `rows` は読取位置 `id`、表示名 `label`、理由 `reason`、取込可能な行だけに `value` を持つ。`applyPlannerImport(state, review, selections)` の選択は `{id, targetKey?, excludeDuplicate?, confirmDistinct?, confirmTotal?}` の配列で渡す。`readPlannerFile(file, kind)` は `../read-grade-file.js` の非同期関数。

## 集計で使う項目

- 履修年度・開講番号・科目名・クラス・学期・科目IDは原本に従い、再取込には `importId` を使う。`matchedCourse` が確認済みの年度別シラバスを表す。年度・科目の対応が不明なら当年のカタログから補完しない。
- 重複単位は `duplicate: true, counts: false`。識別不能な同名行は `identityUncertain`、読替による重複候補は `possibleDuplicate` で履歴に残る。`counts: false` を分野・要件の修得単位から除く。
- 認定科目は `recognized`、大学が示した区分は `allocationLabel` として残す。便覧の区分に一意に対応した場合に `allocationKey` と `allocationScope` が付く。認定済みでも算入区分が不明な科目は個別に要確認とする。
- 帳票の既修得単位は `balances[].current` の区分別合計。適用範囲は `faculty, department, handbook, admitted, program, entry, curriculum, individual, goal, stage`。科目ごとに求めた修得数にこの合計を加えると二重計上になる。全体の合計は、重複単位を除いたことを本人が確認すると `duplicateFree: true` が付く。
- 登録結果は `status[code]` に保存する。不許可の初回確認時には元の授業をコマに表示するため `plan` に残す。結果の記載がない授業の既知の状態を維持する。未計画の授業で結果だけが「要確認」の場合、`status` に記録し、予定単位には加えない。

## 帳票の根拠と検証範囲

大学の画面見本で「不許可となった科目」と開講番号・科目名・講義室・開講期間・単位数の列、およびテキスト出力ボタンを確認した。配布マニュアルは出力ファイル自体の列順や結果記号を定義していない。列や見出しから結果を区別できない場合は「要確認」になる。[学務情報システム留学生向けマニュアル p.6](https://www.niigata-u.ac.jp/wp-content/uploads/2025/03/J_studentweb_manual.pdf#page=7)

公開見本の履修科目確認表は、履修単位と既修得単位にそれぞれ昼間・夜間の欄がある。区分には未表示のものもあり、成績確認表の単位数前の「＊」は原則として重複を示す。科目名変更時の同一扱いと例外は別途照合が必要になる。[経済科学部チェックシート使用マニュアル pp.2–3](https://www.econ.niigata-u.ac.jp/topics/files/elfinder/gakumu/%E3%80%90%E5%BF%85%E8%AA%AD%E3%80%91%E7%B5%8C%E6%B8%88%E7%A7%91%E5%AD%A6%E9%83%A8%E5%8D%92%E6%A5%AD%E8%A6%81%E4%BB%B6%E3%83%81%E3%82%A7%E3%83%83%E3%82%AF%E3%82%B7%E3%83%BC%E3%83%88%E4%BD%BF%E7%94%A8%E3%83%9E%E3%83%8B%E3%83%A5%E3%82%A2%E3%83%AB%E3%80%802025.03%E6%9B%B4%E6%96%B0.pdf#page=2)

成績は評語と単位欄を照合する。創生学部の便覧では、教授会が認定した他大学の授業科目に「認定」と表示する。[学修ガイドブック p.34](https://www.niigata-u.ac.jp/wp-content/uploads/2026/04/01_gakushuu_2026.pdf#page=36)・[創生学部学生便覧 p.14](https://create.niigata-u.ac.jp/public/brochers/R8_ccshandbook.pdf#page=16)

`npm --prefix course_planner test` が合成した行・文字座標・受信パケットを検証する。`node course_planner/test/imports-browser.mjs` は一時ポートの Chrome で架空の日本語PDF・CSV・TSV・ネイティブ受信を確認する。個人の実帳票や学内アカウントでの検証は別途必要になる。
