import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import archive_content as extract


class ContentExtraction(unittest.TestCase):
    def test_percentages_require_complete_literal_assessment_components(self):
        self.assertEqual(extract.weighted_methods("中間試験（32.5％）、期末試験（67.5％）"),
                         [["中間試験", "32.5%"], ["期末試験", "67.5%"]])
        self.assertEqual(extract.weighted_methods("Written examination (75%), participation in class discussions (25%)."),
                         [["Written examination", "75%"], ["participation in class discussions", "25%"]])
        for text in ["試験は実施しない。", "試験60点、課題40点", "期末試験70%", "期末試験は約100%",
                     "出席率100%以上", "期末試験またはレポート100%", "課題50〜100%",
                     "期末試験（100%）を受けない場合もある。", "試験 (30%) またはレポート (70%)",
                     "試験100%。ほかに課題を加点する。", "レポート -100%"]:
            with self.subTest(text=text):
                self.assertEqual(extract.weighted_methods(text), [])
        self.assertEqual(extract.named_methods("試験により評価することはない。"), [])
        self.assertEqual(extract.named_methods("課題レポートで成績を評価する。"), ["課題レポート"])

    def test_delivery_language_and_examples_stay_in_their_source_field(self):
        cells = {"lessons": [], "キーワード": "英語　NICEプログラム　分野横断", "授業実施形態について": "オンラインの場合もある。",
                 "科目の概要": "英語の文献を読む。", "遠隔授業の実施形態": "同時双方向型授業/Interactive"}
        self.assertEqual(extract.facts(cells), {"keywords": ["英語", "NICEプログラム", "分野横断"], "remote": ["同時双方向型授業"]})
        self.assertEqual(extract.language({"科目の概要": "この授業は主に英語で行います。"}), "主に英語")
        self.assertIsNone(extract.language({"科目の概要": "英語で行う。", "備考": "日本語で実施する。"}))
        self.assertEqual(extract.delivery({"授業実施形態について": "原則対面とする。一部は遠隔で行う。"}), "原則対面")
        self.assertEqual(extract.topic_examples([(1, "4/10(金) 研究発表"), (2, "細胞の分化（担当教員）"),
                                                (3, "第3回　受精・種子形成")]), ["受精・種子形成"])
        self.assertEqual(extract.facts({"lessons": []}), {})

    def test_identity_and_source_evidence_fail_closed(self):
        html = "<table><tr><th>開講番号</th><td>260DS217</td></tr><tr><th>開講学期</th><td>2026年度</td></tr></table>"
        self.assertEqual(extract.cells_for(html.encode(), "260DS217")["開講番号"], "260DS217")
        for doc, code in [(html, "260DS218"), (html.replace("2026", "2025"), "260DS217"), ("年度不明", "260DS217")]:
            with self.assertRaises(ValueError):
                extract.cells_for(doc.encode(), code)
        course = {"code": "260DS217", "fields": ["70"], "category": "英語"}
        with self.assertRaises(ValueError):
            extract.verify_fields(course, {"分野": "10：数学", "科目区分": "英語"}, {})
        with self.assertRaises(ValueError):
            extract.verify_fields(course, {"分野": "70：英語", "科目区分": "医歯学"}, {})
        self.assertEqual(extract.verify_fields({**course, "page": 13}, {"分野": "70：英語", "科目区分": "医歯学"}, {}), "70")

    def test_generated_packs_cover_each_offering_once_and_retain_verified_examples(self):
        catalog = json.loads((ROOT / "src/catalog-2026.json").read_text("utf8"))
        expected = {(row["department"], row["code"]) for row in catalog["courses"]}
        rows = {}
        for path in (ROOT / "src/archive/content/packs").glob("*.json"):
            pack = json.loads(path.read_text("utf8"))
            self.assertEqual(path.stem, f"2026-{pack['department']}")
            self.assertEqual(pack["year"], "2026")
            rows.update({(pack["department"], code): record for code, record in pack["courses"].items()})
        self.assertEqual(set(rows), expected)
        self.assertEqual(rows["08", "260DS217"]["weights"], [["Written examination", "75%"], ["participation in class discussions", "25%"]])
        self.assertEqual(rows["84", "261G3008"]["methods"], ["課題レポート"])
        self.assertEqual(rows["84", "261G7011"], {})
        self.assertTrue(rows["01", "260H2049"]["en"])
        self.assertNotIn("language", rows["01", "260H2049"])
        self.assertEqual(rows["09", "260T0017"]["language"], "英語")


if __name__ == "__main__":
    unittest.main()
