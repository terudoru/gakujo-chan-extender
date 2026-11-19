"""Exercise the annual listing join without network access or private records."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from archive_credits import attach_credits, printed_credits


def table(*rows):
    labels = [(140, "開講番号"), (166, "分野１"), (225, "水準"), (264, "科目名"), (308, "単位"), (325, "開講時期")]
    return [(x, 840, t) for x, t in labels] + [item for row in rows for item in row]


def line(y, ending="0105", title="英語Ⅰ", units="１"):
    parts = [(138, "２"), (141, "00G"), (153, ending), (170, "70"), (229, "03"), (240, title),
             (327, "第1,2ターム"), (450, "30")]
    if units:
        parts.append((312, units))
    return [(x, y, t) for x, t in parts]


def search_row(dept="84", code="200G0105", title="英語I"):
    return [dept, code, title, "第1,2ターム", "金1", "70", "0"]


class AnnualCreditsTests(unittest.TestCase):
    def setUp(self):
        self.cover = [(100, 700, "2020年度 授業科目開設一覧")]

    def test_exact_source_including_split_code_and_fraction(self):
        row = line(820, units=None) + [(310, 820.02, "１"), (312.6, 820.02, ".5")]
        printed = printed_credits("2020", [self.cover, table(row, line(802, ending="0106", units=None))])
        rows = [search_row(), search_row(code="200G0106")]
        self.assertEqual(attach_credits("2020", rows, printed), 1)
        self.assertEqual(rows[0][-1], [1.5, 2])
        self.assertEqual(rows[1], search_row(code="200G0106"))
        self.assertEqual(attach_credits("2020", rows, {}), 0)
        self.assertEqual(rows[0], search_row())

    def test_conflicting_rows_and_codes_without_unique_offering_are_unknown(self):
        first = table(line(820))
        printed = printed_credits("2020", [self.cover, first, first])
        for rows in ([search_row(), search_row("01")], [search_row(dept="01")], [search_row(title="英語Ⅱ")],
                     [search_row(code="210G0105")]):
            self.assertEqual(attach_credits("2020", rows, printed), 0)
        for changed in (line(820, units="3"), line(820, title="英語II"), line(820, units=None)):
            printed = printed_credits("2020", [self.cover, first, table(changed)])
            self.assertEqual(attach_credits("2020", [search_row()], printed), 0)
        self.assertEqual(attach_credits("2020", [search_row()], printed_credits("2020", [self.cover, first, first])), 1)

    def test_wrong_cover_missing_heading_or_unclear_unit_cell(self):
        with self.assertRaises(ValueError):
            printed_credits("2021", [self.cover, table(line(820))])
        with self.assertRaises(ValueError):
            printed_credits("2020", [self.cover, [item for item in table(line(820)) if item[2] != "単位"]])
        for x, y in ((312, 820), (318, 820), (312, 820.3)):
            source = table(line(820) + [(x, y, "2")])
            self.assertEqual(attach_credits("2020", [search_row()], printed_credits("2020", [self.cover, source])), 0)


if __name__ == "__main__":
    unittest.main()
