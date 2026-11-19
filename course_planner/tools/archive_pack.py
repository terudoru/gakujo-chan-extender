"""Build lazy year packs after archive_index.py has collected each of its three dimensions.

python archive_pack.py CACHE_DIR YEAR [YEAR ...]
Optional --aliases-layout takes pdf-layout.cjs output for the economics substitution table.
Optional --dental collects only the undergraduate course names in the older faculty index.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import time
import unicodedata

from bs4 import BeautifulSoup
import requests

from archive_index import UNITS

OUT = Path(__file__).resolve().parents[1] / "src/archive"
DENTAL = "https://www.dent.niigata-u.ac.jp/student/syllabus/"
LISTINGS = {
    **{str(y): f"https://www.iess.niigata-u.ac.jp/pdf/subject_list_{y}/all.pdf" for y in (2019, 2020, 2021)},
    "2022": "https://www.niigata-u.ac.jp/wp-content/uploads/2022/03/list2022.pdf",
    "2023": "https://www.niigata-u.ac.jp/wp-content/uploads/2023/03/17_kamoku_2023.pdf",
    "2024": "https://www.niigata-u.ac.jp/wp-content/uploads/2024/03/01_gakushuu_2024.pdf",
    "2025": "https://www.iess.niigata-u.ac.jp/acpb/upload/20250327103752014129200.pdf",
}
GROUPS = ["英語", "初修外国語", "健康・スポーツ", "情報リテラシー", "新潟大学個性化科目",
          "留学生基本科目", "大学学習法", "自然系共通専門基礎", "自然科学", "人文社会・教育科学", "医歯学"]


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def write(path, data):
    path.parent.mkdir(exist_ok=True, parents=True)
    path.write_text(data + "\n", encoding="utf-8", newline="\n")


def alternate_source(session, cache, year, dept, code):
    if year == "2016":
        return "index"
    path = cache / f"{year}-locale-{dept}-{code}.txt"
    if path.exists():
        return path.read_text("utf-8").strip()
    time.sleep(.08)
    url = f"https://syllabus.niigata-u.ac.jp/syllabusHtml/{year}/{dept}/{dept}_{code}_en_US.html"
    response = session.get(url, timeout=20)
    locale = "index"
    if response.status_code != 404:
        response.raise_for_status()
        page = BeautifulSoup(response.content, "html.parser", from_encoding="utf-8")
        cells = {t.get_text(strip=True).split("／")[0]: t.find_next_sibling("td").get_text(strip=True)
                 for t in page.select("tr > th") if t.find_next_sibling("td")}
        if cells.get("開講番号") != code or year + "年度" not in cells.get("開講学期", ""):
            raise ValueError(f"Alternative syllabus metadata mismatch for {year}/{dept}/{code}")
        locale = "en"
    path.write_text(locale, encoding="utf-8")
    return locale


def printed_medical(layout, year):
    # The public A00/A10 filters omit offerings under 医歯学. Read the actual table heading and code column.
    rows = {}
    if not layout or year not in LISTINGS:
        return rows
    for number, page in enumerate(json.loads((layout / f"{year}-layout.json").read_text("utf-8")), 1):
        headings = ["".join(t.split()) for _, _, t in page if "細区分" in t]
        if not headings or not all("医歯学" in t for t in headings):
            continue
        starts = [x for x, _, t in page if t == "開講番号"]
        ends = [x for x, _, t in page if unicodedata.normalize("NFKC", t).replace(" ", "") == "分野1"]
        if not starts or not ends:
            continue
        lines = defaultdict(list)
        for x, y, text in page:
            if starts[0] - 5 < x < ends[0] - 1:
                lines[round(y, 1)].append((x, text))
        for items in lines.values():
            code = unicodedata.normalize("NFKC", "".join(t for _, t in sorted(items))).strip()
            if re.fullmatch(year[-2:] + r"\d[A-Z][A-Z0-9]{4,5}", code):
                rows[code] = number
    return rows


def detail_metadata(session, cache, year, dept, code, locale):
    path = cache / f"{year}-detail-{dept}-{code}.json"
    if path.exists():
        return json.loads(path.read_text("utf-8"))
    suffix = "en_US" if locale == "en" else "ja_JP"
    url = f"https://syllabus.niigata-u.ac.jp/syllabusHtml/{year}/{dept}/{dept}_{code}_{suffix}.html"
    time.sleep(.08)
    response = session.get(url, timeout=20)
    if response.status_code == 404:
        return None
    response.raise_for_status()
    page = BeautifulSoup(response.content, "html.parser", from_encoding="utf-8")
    cells = {t.get_text(strip=True).split("／")[0]: t.find_next_sibling("td").get_text(" ", strip=True)
             for t in page.select("tr > th") if t.find_next_sibling("td")}
    if cells.get("開講番号") != code or year + "年度" not in cells.get("開講学期", ""):
        raise ValueError(f"Detail metadata mismatch for {year}/{dept}/{code}")
    category = re.split(r"[\s／]", cells.get("科目区分", ""))[0]
    group = format(GROUPS.index(category), "X") if category in GROUPS else ""
    result = [group, re.findall(r"(\d{2})\s*[:：]", cells.get("分野", ""))]
    path.write_text(compact(result), encoding="utf-8")
    return result


def build(session, cache, year, layouts):
    offerings, fields, categories = {}, defaultdict(set), defaultdict(set)
    for dim, expected in [("jikanwariShozokuCode", len(UNITS)), ("bunya", 56), ("saikbn", 37)]:
        paths = sorted(cache.glob(f"{year}-{dim}-*.json"))
        if len(paths) != expected:
            raise ValueError(f"Incomplete {year} {dim}: {len(paths)} of {expected} search filters")
        for path in paths:
            value = path.stem.split("-")[-1]
            for dept, code, title, term, slot, *availability in json.loads(path.read_text("utf-8")):
                key = (dept, code)
                if dim == "jikanwariShozokuCode":
                    if dept != value or not code.startswith(year[-2:]):
                        raise ValueError(f"Unverified identity {year} {key}")
                    if offerings.setdefault(key, [title, term, slot, *availability]) != [title, term, slot, *availability]:
                        raise ValueError(f"Inconsistent offering {year} {key}")
                elif offerings.get(key) != [title, term, slot, *availability]:
                    raise ValueError(f"Search results disagree on {year} {key}")
                elif dim == "bunya" and value != "00":
                    fields[key].add(value)
                elif dim == "saikbn":
                    categories[key].add(value[0])
    if not offerings:
        raise ValueError(f"Empty year {year}")
    rows = []
    printed = printed_medical(layouts, year)
    for (dept, code), (title, term, slot, *availability) in sorted(offerings.items()):
        key = (dept, code)
        group = categories[key]
        if len(group) > 1:
            raise ValueError(f"Conflicting categories {key}")
        locale = alternate_source(session, cache, year, dept, code) if availability else ""
        page = 0
        detail_fields = False
        if not group and code in printed:
            page = printed[code]
            group.add("A")
        if year != "2016" and locale != "index" and (not group or not fields[key]):
            detail = detail_metadata(session, cache, year, dept, code, locale)
            if detail is None:
                locale = "index"
            else:
                actual_group, actual_fields = detail
                if group and actual_group not in group or fields[key] and set(actual_fields) != fields[key]:
                    raise ValueError(f"Detail disagrees with search or printed listing for {year}/{code}")
                if actual_group:
                    group.add(actual_group)
                detail_fields = not fields[key] and bool(actual_fields)
                fields[key].update(actual_fields)
        extra = [locale, page, True] if detail_fields else [locale, page] if page else [locale] if locale else []
        rows.append(compact([dept, code, title, term, slot, "".join(sorted(fields[key])), next(iter(group), ""), *extra]))
    header = {"year": year}
    if printed:
        header["listing"] = LISTINGS[year]
    data = compact(header)[:-1] + ',"rows":[\n' + ",\n".join(rows) + '\n]}'
    write(OUT / "packs" / f"{year}.json", data)
    print(year, len(rows), sum(bool(f) for f in fields.values()), flush=True)


def aliases(layout):
    pairs = []
    for page_no, page in enumerate(json.loads(layout.read_text("utf-8")), 1):
        rows = defaultdict(list)
        for x, y, title in page:
            rows[round(y)].append((x, title))
        header, *courses = [sorted(rows[y]) for y in sorted(rows, reverse=True)]
        if "【経済科学部】" not in header[0][1] or "【経済学部】" not in header[1][1]:
            raise ValueError("Changed economics table headers")
        for row in courses:
            (x_new, new), (x_old, old) = row
            if not (35 < x_new < 45 and 256 < x_old < 270):
                raise ValueError("Unexpected economics table columns")
            if new != old:
                pairs.append([new, old, page_no])
    write(OUT / "economics-aliases.json", "[\n" + ",\n".join(map(compact, pairs)) + "\n]")


def current_sources(session, cache):
    catalog = json.loads((OUT.parent / "catalog-2026.json").read_text("utf-8"))
    present = {c["code"]: c for c in catalog["courses"]}
    public = {r[1]: r for unit in UNITS for r in json.loads(
        (cache / f"{catalog['year']}-jikanwariShozokuCode-{unit}.json").read_text("utf-8"))}
    if public.keys() != present.keys():
        raise ValueError("Refresh the active catalog before updating its syllabus links")
    field_filters = sorted(cache.glob(f"{catalog['year']}-bunya-*.json"))
    if len(field_filters) != 56:
        raise ValueError("Incomplete active-year academic field filters")
    fields = defaultdict(set)
    for path in field_filters:
        for _, code, *_ in json.loads(path.read_text("utf-8")):
            if path.stem[-2:] != "00":
                fields[code].add(path.stem[-2:])
    overrides = {}
    for code, (dept, _, title, term, slot, *availability) in public.items():
        if present[code]["department"] != dept or present[code]["title"] != title:
            raise ValueError(f"Active catalog differs from public search: {code}")
        override = {}
        if availability:
            override["locale"] = alternate_source(session, cache, str(catalog["year"]), dept, code)
        if fields[code] != set(present[code]["fields"]):
            metadata = detail_metadata(session, cache, str(catalog["year"]), dept, code, override.get("locale"))
            if metadata is None:
                raise ValueError(f"Cannot verify differing active-year fields: {code}")
            override["fields"] = metadata[1]
        if override:
            overrides[code] = override
    write(OUT / "current-sources.json", compact(overrides))


def dental():
    response = requests.get(DENTAL, timeout=30)
    response.raise_for_status()
    page = BeautifulSoup(response.content, "html.parser", from_encoding="utf-8")
    result = {}
    for heading in page.select("h2[id^=p1-syl]"):
        year = heading["id"].removeprefix("p1-syl")
        faculty = heading.find_next_sibling("h3")
        if not re.fullmatch(r"\d{4}", year) or "歯学部" not in faculty.get_text():
            raise ValueError("Unexpected dental archive heading")
        titles = []
        for block in faculty.find_next_siblings():
            if block.name in ["h2", "h3"]:
                break
            for a in block.select("ul > li > a"):
                title = a.get_text(strip=True)
                if not re.search("時間割|対応表|教員|講義概要", title):
                    titles.append(title)
        result[year] = list(dict.fromkeys(titles))
    write(OUT / "dental-index.json", json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("years", nargs="*")
    parser.add_argument("--aliases-layout", type=Path)
    parser.add_argument("--layouts", type=Path, help="Directory containing YEAR-layout.json from pdf-layout.cjs for LISTINGS")
    parser.add_argument("--dental", action="store_true")
    parser.add_argument("--current-sources", action="store_true")
    args = parser.parse_args()
    with requests.Session() as session:
        for y in args.years:
            build(session, args.cache, y, args.layouts)
        if args.current_sources:
            current_sources(session, args.cache)
    if args.aliases_layout:
        aliases(args.aliases_layout)
    if args.dental:
        dental()
