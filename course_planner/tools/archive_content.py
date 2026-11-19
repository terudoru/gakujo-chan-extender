"""Build the comparison facts from individual public syllabus pages.

python tools/archive_content.py PATH_TO_HTML_CACHE [--download-only]
Reuses validated HTML in the cache by official filename. Use a fresh cache to refresh.
Requests, beautifulsoup4 and lxml are required. No portal session or student input is used.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
import json
from pathlib import Path
import re
import threading
import time
import unicodedata

from bs4 import BeautifulSoup
import requests

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/archive/content/packs"
YEAR = "2026"
SESSIONS = threading.local()


def normalize(value):
    return " ".join(unicodedata.normalize("NFKC", value).split())


def cells_for(html, code):
    page = BeautifulSoup(html, "lxml", from_encoding="utf-8")
    fields = {}
    for th in page.select("tr > th"):
        td = th.find_next_sibling("td")
        if td:
            key = th.get_text(strip=True).split("／")[0].strip()
            fields[key] = "\n".join(s.strip() for s in td.stripped_strings)
    if fields.get("開講番号") != code or not re.match(rf"{YEAR}\s*年度", fields.get("開講学期", "")):
        raise ValueError(f"Syllabus identity mismatch: {code}")
    # Use only the numbered content column, never the out-of-class work, notes or lecturer columns.
    lessons = []
    for table in page.find_all("table"):
        header = table.find("tr")
        columns = [normalize(t.get_text(strip=True)).split("/")[0] for t in header.find_all("th", recursive=False)] if header else []
        if columns[:2] != ["No.", "内容"]:
            continue
        for row in table.find_all("tr")[1:]:
            cells = row.find_all("td", recursive=False)
            if len(cells) == len(columns) and re.fullmatch(r"\d{1,2}", cells[0].get_text(strip=True)):
                lessons.append((int(cells[0].get_text(strip=True)), cells[1].get_text(" ", strip=True)))
    fields["lessons"] = lessons
    return fields


def source_filename(course, overrides):
    department, code = course["department"], course["code"]
    if not re.fullmatch(r"[0-9A-Z]{2}", department) or not re.fullmatch(r"26\d[A-Z][A-Z0-9]{4,5}", code):
        raise ValueError("Unexpected public catalog identity")
    locale = overrides.get(code, {}).get("locale")
    if locale not in (None, "en"):
        raise ValueError(f"No verified detail URL for {code}")
    return f"{department}_{code}_{'en_US' if locale == 'en' else 'ja_JP'}.html"


def course_cells(cache, course, overrides):
    code = course["code"]
    filename = source_filename(course, overrides)
    path = cache / filename
    if path.exists():
        return cells_for(path.read_bytes(), code)
    url = f"https://syllabus.niigata-u.ac.jp/syllabusHtml/{YEAR}/{course['department']}/{filename}"
    if not hasattr(SESSIONS, "client"):
        SESSIONS.client = requests.Session()
    for attempt in range(3):
        try:
            time.sleep(.2)
            response = SESSIONS.client.get(url, timeout=20, allow_redirects=False)
            if response.status_code != 200:
                raise requests.HTTPError(f"{code}: HTTP {response.status_code}", response=response)
            fields = cells_for(response.content, code)
            temp = path.with_suffix(".tmp")
            temp.write_bytes(response.content)
            temp.replace(path)
            return fields
        except requests.RequestException:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


# Only short noun phrases are retained. Published narratives, grading thresholds and contact details stay at source.
def short_term(text, max_length):
    term = normalize(text).strip(" ★☆※・:：")
    if not 1 < len(term) <= max_length or not re.search(r"[A-Za-zぁ-んァ-ヶ一-龯]", term):
        return None
    if re.search(r"https?:|www\.|[@<>。!?！？\n]|\d{2,4}[-ー]\d{2,4}[-ー]\d{3,4}|"
                 r"します|しますが|である|行う|ください|予定|可能性|担当|先生|教授|准教授|メール|連絡先|"
                 r"非対面|対面型|実務経験|実務家教員|記載なし|特になし|non.face.to.face|face.to.face class|"
                 r"^なし$|^none$|^n/?a$|^tba$|^tbd$", term, re.I):
        return None
    if term.count("(") != term.count(")") or len(term.split()) > 6:
        return None
    return term


def keywords(value):
    terms = []
    for chunk in re.split(r"[,，、;；\n\t\u3000]", value):
        # Spaces delimit Japanese keyword lists; keep English multi-word terms intact.
        parts = re.split(r"\s+", chunk.strip()) if re.fullmatch(r"[\u3000-\u9fff\uff00-\uffef\s]+", chunk) else [chunk]
        for part in parts:
            term = short_term(part, 30)
            if term and term not in terms:
                terms.append(term)
    return terms[:5]


def topic_examples(lessons):
    topics, seen = [], set()
    for number, text in lessons:
        term = re.sub(r"^(?:第\s*\d+\s*回|(?:Lesson|Week|Unit)\s*\d+\b|\d+[.、:])\s*[:：・-]?\s*", "", normalize(text), flags=re.I)
        # The timetable sometimes includes dates, room numbers or lecturer names inside the topic cell.
        if re.search(r"\d+[/月]\d+|\d+\s*限|\d+:\d{2}|教室|担当|(?:先生|教授)|[（(][一-龯、・ 々]{1,13}[)）]", term):
            continue
        term = short_term(term, 27)
        if not term or re.search(r"ガイダンス|オリエンテーション|試験|テスト|まとめ|授業の概要|"
                                 r"イントロダクション|教科書|履修|振り返り|発表会|報告会|レポート提出|成績評価|を学ぶ|について学|する$|した$|[。;；]"
                                 r"|^(授業|講義|研究|演習|実習|実験|発表|課題|学習|ゼミ|卒業研究|続き|復習|\d+)[\s\d()回IVX]*$"
                                 r"|orientation|guidance|\b(?:test|exam|review|summary|syllabus)\b|^(?:unit|chapter|week|lesson|class)\s*[\d\s:-]+$", term, re.I):
            continue
        key = re.sub(r"[0-9①-⑳\s()IVX]+$", "", term)
        if key and key not in seen:
            topics.append(term)
            seen.add(key)
    return [topics[0], topics[len(topics) // 2]] if len(topics) > 1 else topics


LANGUAGES = "日本語|英語|ドイツ語|中国語|フランス語|スペイン語|ロシア語|韓国語|朝鮮語"


def language(fields):
    text = "\n".join(fields.get(k, "") for k in ["使用言語", "教授言語", "科目の概要", "授業実施形態について", "備考"])
    found = set()
    lang = rf"((?:{LANGUAGES})(?:(?:と|・|および)(?:{LANGUAGES}))?)"
    for sentence in re.split(r"[。.!?\n]", text):
        s = normalize(sentence).strip("・ ")
        m = re.fullmatch(rf"(?:なお[,、]?)?(?:(?:本|この)?(?:授業|講義|演習)(?:は|を)[、,]?)?\s*"
                         rf"(主に|主として|原則として|原則|すべて|全て)?\s*{lang}(?:で|にて|を用いて|により)"
                         r"(?:授業|講義|演習)?(?:を)?(?:行います|行う|行われます|行われる|実施する|実施します|進める|進めます)", s)
        if not m:
            m = re.fullmatch(rf"(?:授業言語|使用言語|教授言語)\s*[:は]\s*(){lang}(?:です|とする)?", s)
        if m:
            found.add(("主に" if m[1] in ("主に", "主として") else "原則" if m[1] in ("原則", "原則として") else "") + m[2])
        en = re.fullmatch(r"(?:this|the) (?:class|course|lectures?) (?:is|are|will be) (?:taught|conducted|delivered) "
                          r"(mainly |primarily |entirely |only )?in (English|Japanese)", s, re.I)
        if en:
            found.add(("主に" if (en[1] or "").lower().strip() in ("mainly", "primarily") else "") +
                      ("英語" if en[2].lower() == "english" else "日本語"))
    return next(iter(found)) if len(found) == 1 else None


def delivery(fields):
    s = normalize(fields.get("授業実施形態について", "")).lstrip("・ ")
    if re.match(r"^(?:(?:本|この)?(?:授業|講義)(?:は|を)[、,]?\s*)?(?:原則(?:として)?|基本的に)\s*対面(?:型|形式|授業)?"
                r"(?:とする|で(?:実施|行)|です|である|を基本)", s) or re.match(r"^対面授業を基本と", s):
        return "原則対面"
    # Mixed, hypothetical and negative references to face-to-face classes are not evidence of a primary mode.
    if not re.search(r"オンライン|遠隔|非対面|オンデマンド|場合|一部|予定|変更", s) and re.fullmatch(
            r"(?:本授業は[,、]?\s*)?対面(?:授業|形式|型授業|型)?(?:で(?:実施(?:する|します)|行(?:う|います)))?[。.]?", s):
        return "対面"
    return None


PERCENT = re.compile(r"(\d{1,3}(?:\.\d+)?)\s*%")
METHOD = re.compile(r"試験|テスト|レポート|報告|論文|課題|発表|プレゼン|スピーチ|態度|参加|取[りリ]?組み|"
                    r"能力|質疑応答|平常点|討論|議論|発言|実習|実験|演習|作品|提出|評価|学習状況|深度|"
                    r"exams?|examinations?|tests?|quizz?(?:es)?|reports?|assignments?|participation|presentations?|"
                    r"attendance|homework|papers?|projects?|discussions?", re.I)


def weighted_methods(text):
    s = unicodedata.normalize("NFKC", text)
    numbers = [Decimal(n) for n in PERCENT.findall(s)]
    if not 1 <= len(numbers) <= 6 or any(n <= 0 for n in numbers) or sum(numbers) != 100:
        return []
    if re.search(r"以上|以下|未満|上限|下限|程度|場合|およそ|概ね|約\s*\d|再試験|出席率|合格率|得点率|"
                 r"変更|替え|免除|または|又は|あるいは|もしくは|を主とし|目安|加点|減点|考慮|変動|"
                 r"[〜~]|at least|up to|approximately|\b(?:or|bonus|deducted|unless)\b", s, re.I):
        return []
    weighted = []
    for part in re.split(r"[。;；\n]|(?<!\d)\.(?=\s|$)|(?<=%)\.(?=\s|$)", s):
        if "%" not in part:
            continue
        end = 0
        for m in PERCENT.finditer(part):
            raw = part[end:m.start()].strip()
            raw = re.sub(r"^[)\]】]*\s*(?:(?:[,、・●:]+|及び|および|ならびに|そして|and\b|と)\s*)*", "", raw, flags=re.I)
            raw = re.sub(r"^(?:成績の?評価は|評価は|配点は|配点|評価方法)\s*[:,、]?\s*", "", raw)
            label = raw.rstrip(" (:【[")
            if not (1 < len(label) <= 44 and METHOD.search(label)) or re.search(
                    r"[\d%:,、;。!?⇒=+*/<>@【】\[\]]|[-−]\s*$|につい|ため|とする|行う$|(?:する|です|ます|ません|ない)|"
                    r"\b(?:not|if|only|without|including)\b", label, re.I):
                return []
            if len(label.split()) > 6 or label.count("(") != label.count(")"):
                return []
            weighted.append([label, m[1] + "%"])
            end = m.end()
        tail = part[end:].strip().lstrip(")]】 、,")
        if not re.fullmatch(r"(?:(?:により|で|によって|を|から|に基づいて|に基づき)(?:成績を)?(?:総合的に)?"
                            r"(?:成績を)?(?:評価|算出|判定)(?:する|します|を行う))?[.。]?", tail):
            return []
    if len(weighted) != len(numbers) or len({a for a, _ in weighted}) != len(weighted):
        return []
    return weighted


def named_methods(text):
    # Only explicit affirmative evaluation statements. A mere mention or a negated exam is not sufficient.
    methods = []
    for sentence in re.split(r"[。\n]", normalize(text)):
        if re.search(r"ない|ません|未提出|場合|条件|欠席|または|必要|\d+%", sentence):
            continue
        for m in re.finditer(r"(期末レポート|課題レポート|実習レポート|小レポート|レポート|期末試験|中間試験|"
                             r"筆記試験|定期試験|小テスト|プレゼンテーション|研究発表)(?:のみ)?(?:で|により|によって|をもとに|に基づいて)"
                             r"(?:成績を|総合的に)?評価(?:する|します|を行う)", sentence):
            if m[1] not in methods:
                methods.append(m[1])
    return methods[:4]


def facts(fields):
    terms = keywords(fields.get("キーワード", ""))
    assessment = fields.get("成績評価の方法と基準", "")
    weights = weighted_methods(assessment)
    remote = fields.get("遠隔授業の実施形態", "")
    facts = {
        "keywords": terms,
        "topics": [] if terms else topic_examples(fields["lessons"]),
        "language": language(fields),
        "mode": delivery(fields),
        "remote": [v for v in ("同時双方向型授業", "オンデマンド型授業") if v in remote],
        "weights": weights,
        "methods": [] if weights else named_methods(assessment),
    }
    return {key: val for key, val in facts.items() if val}


def verify_fields(course, cells, overrides):
    code = course["code"]
    reported = sorted(set(re.findall(r"(\d{2})\s*[:：]", cells.get("分野", ""))))
    saved = sorted(set(overrides.get(code, {}).get("fields", course["fields"])))
    if saved != reported:
        raise ValueError(f"Academic fields differ from the individual syllabus: {code}, {saved} vs {reported}")
    if not course.get("page") and re.split(r"[\s／]", cells.get("科目区分", ""))[0] != course["category"]:
        raise ValueError(f"Category lacks a corroborating source: {code}")
    return "".join(reported)


def field_ranges(checked):
    # Only consecutive codes within a department, prefix, width and exact field set share a range.
    groups = defaultdict(list)
    for department, code, fields in sorted(checked):
        match = re.fullmatch(r"(\d{3}[A-Z]+)(\d+)", code)
        suffix = match[2]
        ranges = groups[f"{department}/{match[1]}/{len(suffix)}"]
        number = int(suffix)
        if ranges and ranges[-1][1] == number - 1 and ranges[-1][2] == fields:
            ranges[-1][1] = number
        else:
            ranges.append([number, number, fields])
    return groups


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("--download-only", action="store_true")
    args = parser.parse_args()
    args.cache.mkdir(exist_ok=True, parents=True)
    catalog = json.loads((ROOT / "src/catalog-2026.json").read_text("utf-8"))
    overrides = json.loads((ROOT / "src/archive/current-sources.json").read_text("utf-8"))
    courses = catalog["courses"]
    if str(catalog["year"]) != YEAR or len({c["code"] for c in courses}) != len(courses):
        raise ValueError("Catalog year or unique course identity unavailable")
    packs = defaultdict(dict)
    checked = []
    coverage = Counter()
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = pool.map(lambda c: course_cells(args.cache, c, overrides), courses)
        for i, (course, cells) in enumerate(zip(courses, results, strict=True), 1):
            if not args.download_only:
                code = course["code"]
                checked.append((course["department"], code, verify_fields(course, cells, overrides)))
                data = facts(cells)
                coverage.update(list(data))
                if overrides.get(code, {}).get("locale") == "en":
                    data["en"] = True
                packs[course["department"]][code] = data
            if i % 500 == 0 or i == len(courses):
                print(f"Verified {i}/{len(courses)}", flush=True)
    if not args.download_only:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for department, entries in sorted(packs.items()):
            path = OUTPUT / f"{YEAR}-{department}.json"
            pack = {"year": YEAR, "department": department, "courses": dict(sorted(entries.items()))}
            write_json(path, pack)
        write_json(OUTPUT.parent / "field-evidence-2026.json", field_ranges(checked))
        print(dict(coverage))


if __name__ == "__main__":
    main()
