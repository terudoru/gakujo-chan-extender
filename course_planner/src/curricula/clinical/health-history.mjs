import { combined, credits, decision, norm, source, stage } from "./rules.mjs";

// 学科の令和4年度時間割には、改正前の2～4年次配当と旧 M5 系列の開講番号が載る。
const schedule = "https://www.clg.niigata-u.ac.jp/editor/upload/admina51df0c3efee039d38623cac6b08d216/files/" +
  "令和4年度保健学科時間割学部V5_2022_9_27.pdf";
const tables = [
  [
    [["M5137", "小児看護学"], ["M5133", "疾病の成因と治療Ⅰ"], ["M5132", "エイジング看護論"], ["M5149", "精神看護学"], [
      "M5123",
      "クリティカルケア論",
    ]],
    [["M5140", "小児生活支援看護論"], ["M5171", "チーム医療実践論"], ["M5167", "看護過程展開技術演習Ⅱ"], [
      "M5134",
      "エイジング看護演習",
    ]],
    [["M5120", "看護管理経営論"], ["M5173", "看護研究演習Ⅱ"]],
  ],
  [
    [["M5320", "放射線関係法規及び演習"], ["M5318", "放射線生物学及び演習"], ["M5313", "放射線計測学Ⅰ及び演習"], [
      "M5337",
      "放射線撮影技術学Ⅰ",
    ]],
    [["M5314", "放射線計測学Ⅱ"], ["M5356", "放射線治療技術学Ⅲ"], ["M5344", "医用画像処理工学"], [
      "M5350",
      "核医学検査技術学Ⅱ",
    ], ["M5321", "放射線管理学及び演習"]],
    [["M5361", "放射線科学セミナー"], ["M5360", "卒業研究"]],
  ],
  [
    [["M5521", "医用工学概論"], ["M5544", "病原微生物学"], ["M5546", "微生物検査科学"], ["M5501", "人体機能構造学Ⅰ"], [
      "M5502",
      "人体機能構造学Ⅱ",
    ]],
    [["M5524", "病気の成り立ちⅠ"], ["M5525", "病気の成り立ちⅡ"], ["M5512", "循環器機能検査科学"], [
      "M5508",
      "ゲノム検査科学",
    ], ["M5541", "病理形態学実習Ⅰ"]],
    [["M5526", "疾患と臨床検査"], ["M5557", "臨床検査実習"]],
  ],
];
const prescribed = [
  [["M5504", "生体機能学実習"], ["M5503", "人体構造学実習"], ["M5555", "臨床検査管理概論"]],
  [["M5025", "救急救護法"], ["M5522", "医用工学実習"], ["M5540", "病理形態学Ⅱ"]],
  [["M5558", "卒業研究"]],
];
export function healthArchive(year, index) {
  if (year < 2019 || year > 2021 || index < 0) return null;
  const grade = 2022 - year + 1, slot = grade - 2;
  const src = source(
    "令和4年度 保健学科時間割・" + grade + "年次",
    encodeURI(schedule) + "#page=" + (3 + index * 3 + slot),
  );
  const courseRow = ([code, title], kind) => ({
    ...credits(
      "old-" + code,
      title,
      1,
      (c) => {
        if (norm(c.title) !== norm(title)) return false;
        if (c.department && c.department !== "07") return false;
        if (!c.code) return null;
        if (c.year && Number(c.year) !== 2022) return null;
        return new RegExp("^22[0-4]" + code + "$").test(c.code);
      },
      src,
      { kind, unit: "courses" },
    ),
    year: grade,
  });
  const named = tables[index][slot].map((item) => courseRow(item, "旧課程の時間割配当"));
  const designated = index === 2 ? prescribed[slot].map((item) => courseRow(item, "選択・履修指定")) : [];
  const match = combined(...[...named, ...designated].map((r) => r.match));
  const studyStage = stage("legacy-year-" + grade, "旧課程・" + grade + "年次の履修科目", "progress", [
    ...named,
    ...designated,
    decision(
      "old-timetable",
      "当時の時間割と進級判定",
      "令和4年度時間割の当該学年・専攻に配当された科目を表示します。休学・留年による履修時期のずれ、読替、全必修の修得は保健学科学務係で確認してください。",
      src,
    ),
  ], [src]);
  return { studyStage, src, match: (c) => match(c) === true ? true : c.department === "84" ? false : null };
}
