"""Join credits from the units column of an official annual offering list to its public search index."""
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import unicodedata


LISTINGS = json.loads((Path(__file__).resolve().parents[1] / "src/archive/credit-listings.json").read_text("utf-8"))
CODE = re.compile(r"[0-9]{3}[A-Z][A-Z0-9]{4,5}")
UNITS = re.compile(r"(?:[1-9][0-9]?|0)(?:\.[0-9]+)?")
# Fourth character of 開講番号, as defined in the annual list's numbering guide.
# 経済学部 and 経済科学部 share E. Their individual offering departments come from the annual search.
DEPARTMENTS = {"G": {"84"}, "Q": {"84"}, "H": {"01"}, "K": {"03"}, "L": {"04"}, "E": {"05", "0C"},
               "S": {"06"}, "M": {"07"}, "D": {"08"}, "T": {"09"}, "A": {"0A"}, "X": {"0B"}}


def normalized(text):
    return "".join(unicodedata.normalize("NFKC", text).split())


def header_columns(items):
    labels = {t: x for x, t in items}
    first_field = labels.get("分野1")
    if first_field is None:  # The 2017 economics section labels these 分類１, 分類２, 分類３.
        first_field = next((x for (x, t), (_, n) in zip(items, items[1:]) if t == "分類" and n == "1"), None)
    level = labels.get("水準")
    if level is None:
        level = labels.get("水準科目名")  # One positioned item in parts of the 2022 PDF.
    elif not level < labels.get("科目名", 0) < labels.get("単位", 0):
        return None
    cols = [labels.get("開講番号"), first_field, level, labels.get("単位"), labels.get("開講時期", labels.get("学期"))]
    return cols if None not in cols and cols == sorted(set(cols)) else None


def units_in_cell(items):
    # Some PDFs draw digits individually. Only adjacent glyphs on one baseline can form a number.
    for (x, text), (next_x, _) in zip(items, items[1:]):
        if not 1 < next_x - x < 4 * len(text):
            return None
    cell = "".join(t for _, t in items)
    if not UNITS.fullmatch(cell):
        return None
    value = float(cell)
    return int(value) if value.is_integer() else value


def table_rows(lines, top, bottom, columns):
    code_x, field_x, level_x, units_x, term_x = columns
    body = [(y, items) for y, items in lines if bottom < y < top]
    starts = []
    for y, items in body:
        code = "".join(t for x, t in items if code_x - 5 < x < field_x - 1)
        if CODE.fullmatch(code):
            starts.append((y, code))
    for i, (y, code) in enumerate(starts):
        # Titles may wrap above and below their code. Never cross the midpoint to the next code.
        upper = min(y + 10, (starts[i - 1][0] + y) / 2 if i else top)
        lower = max(y - 10, (starts[i + 1][0] + y) / 2 if i + 1 < len(starts) else bottom)
        title = "".join(t for by, items in body if lower < by < upper
                        for x, t in items if level_x + 10 < x < units_x - 4)
        cell_lines = [[(x, t) for x, t in items if units_x - 4 <= x < term_x - 5]
                      for by, items in body if abs(by - y) <= 0.5]
        cells = [items for items in cell_lines if items]
        yield code, title, units_in_cell(cells[0]) if len(cells) == 1 else None


def printed_credits(year, pages):
    number = int(year)
    cover = normalized("".join(t for page in pages[:8] for _, _, t in page))
    era = f"令和{number - 2018}年度" if number >= 2019 else f"平成{number - 1988}年度"
    if year + "年度" not in cover and era not in cover:
        raise ValueError(f"Cannot verify academic year on cover of {year} listing")
    printed = defaultdict(list)
    for page_no, page in enumerate(pages, 1):
        if not any(normalized(t) == "開講番号" for _, _, t in page):
            continue
        baselines = defaultdict(list)
        for x, y, text in page:
            baselines[round(y, 1)].append((x, normalized(text)))
        lines = [(y, sorted(items)) for y, items in sorted(baselines.items(), reverse=True)]
        headers = []
        for y, items in lines:
            if any(t == "開講番号" for _, t in items):
                headers.append((y, header_columns(items)))
        for i, (top, cols) in enumerate(headers):
            if cols:
                bottom = headers[i + 1][0] if i + 1 < len(headers) else 0
                for code, title, value in table_rows(lines, top, bottom, cols):
                    if code.startswith(year[-2:]):
                        printed[code].append((title, value, page_no))
    if not printed:
        raise ValueError(f"No annual course table recognized for {year}")
    return printed


def attach_credits(year, rows, printed):
    # The PDF identifies offerings by number, not by the target audience printed in its faculty column.
    # Recover the offering department only from an unambiguous full code in this year's public search.
    count = Counter(row[1] for row in rows)
    evidence_count = 0
    for row in rows:
        if isinstance(row[-1], list):
            row.pop()  # Deterministic refresh, including removal of stale evidence.
        department, code, title = row[:3]
        if not CODE.fullmatch(code) or not code.startswith(year[-2:]) or count[code] != 1:
            continue
        if department not in DEPARTMENTS.get(code[3], set()):
            continue
        records = printed.get(code, [])
        values = {(name, units) for name, units, _ in records}
        if len(values) == 1:
            name, units = values.pop()
            if name == normalized(title) and units is not None and units > 0:
                row.append([units, records[0][2]])
                evidence_count += 1
    return evidence_count
