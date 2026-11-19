"""Refresh factual 2026 undergraduate metadata. Requires requests, beautifulsoup4 and Node.
Run from any directory: python tools/build_catalog.py
The public syllabus supplies course identity and paired meeting slots. The printed
course listing supplies credits and academic fields. Never derive fields from course names.
"""
import argparse
from contextlib import nullcontext
import json
import re
import subprocess
import tempfile
import time
import unicodedata
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
SEARCH = "https://syllabus.niigata-u.ac.jp/campus-sy/"
LISTING = "https://www.iess.niigata-u.ac.jp/acpb/upload/20260327161315092692700.pdf"
YEAR = 2026
UNITS = ("01", "03", "04", "05", "0C", "06", "07", "08", "09", "0A", "0B", "84")
CODE = re.compile(r"[0-9]{2}[0-9A-Z][A-Z][0-9A-Z]{4,5}")
WEEK = "月火水木金土日"


def clean(value):
    return unicodedata.normalize("NFKC", value).strip()


def soup(response):
    response.raise_for_status()
    return BeautifulSoup(response.content, "html.parser", from_encoding="utf-8")


def printed_metadata(pages):
    fields, records = {}, {}
    for x, y, s in pages[3]:
        if 140 < y < 660 and (139 < x < 144 or 279 < x < 283) and re.fullmatch(r"\d{2}", clean(s)):
            label = next((v for xx, yy, v in pages[3] if abs(yy-y) < 1 and 18 < xx-x < 24), "")
            fields[clean(s)] = clean(label)
    for number, items in enumerate(pages, 1):
        if not 8 <= number <= 135:
            continue
        for x, y, raw in items:
            code = clean(raw)
            if not (45 <= x < 76 and CODE.fullmatch(code)):
                continue
            row = [(xx, clean(t)) for xx, yy, t in items if abs(yy-y) < 1.25]
            headers = [(yy, t) for xx, yy, t in items if "細区分" in clean(t) and yy > y and xx < 200]
            category = ""
            if headers:
                header_y = min(yy for yy, _ in headers)
                header = "".join(t for xx, yy, t in items if 42 < xx < 325 and abs(yy-header_y) < 1)
                category = re.sub(r"\s", "", clean(header)).split("(細区分")[0]
            credits = next((float(t) for xx, t in row if 215 < xx < 232 and re.fullmatch(r"\d+(?:\.\d+)?",t)), None)
            formats = [clean(v) for xx, yy, v in items if 523 < xx < 555 and abs(yy-y) < 5]
            record = {"credits": credits, "fields": [t for xx,t in row if 76 <= xx <= 129 and t in fields],
                      "category": category, "format": "".join(formats).replace(" ", ""), "page": number}
            if code in records and records[code] != record:
                raise ValueError(f"Conflicting course metadata for {code}")
            records[code] = record
    if len(records) < 4000 or fields.get("70") != "英語":
        raise ValueError("Unexpected layout of university course listing")
    return fields, records


def get_courses(session, department, term="", field=""):
    response = session.get(SEARCH, timeout=25)
    form = soup(response).select_one('form[name=KeywordForm]')
    if not form:
        raise ValueError("Public search form unavailable")
    values = {tag["name"]: tag.get("value","") for tag in form.select('input[name]:not([type=button]),select[name]')}
    values.update(nendo=str(YEAR), jikanwariShozokuCode=department, kaikoKubunCode=term,
                  bunya=field, _displayCount="200")
    page = soup(session.post(urljoin(SEARCH,form["action"]), data=values,timeout=30))
    if "最大表示件数" in page.get_text():
        # Narrow an oversized public query using the actual search form options.
        selector, argument = ("kaikoKubunCode","term") if not term else ("bunya","field")
        if field:
            raise ValueError(f"Public query is still too large: {department}/{term}/{field}")
        for option in form.select(f'select[name="{selector}"] option[value]'):
            if option["value"]:
                params = {"term":term,"field":field,argument:option["value"]}
                yield from get_courses(session, department, **params)
        return
    while True:
        for button in page.select('input[value="和文"][onclick]'):
            tr = button.find_parent('tr')
            cols = [c.get_text(' ',strip=True) for c in tr.find_all('td', recursive=False)]
            if len(cols) != 8:
                raise ValueError("Unexpected public syllabus results")
            semester, term_label, schedule, code, title, teacher = map(clean,cols[1:7])
            if not CODE.fullmatch(code):
                continue
            yield {"code":code,"department":department,"title":title,"teacher":teacher,
                   "semester":semester,"period":term_label,"schedule":schedule}
        next_link = next((a for a in page.select('a[href]') if "次へ" in a.get_text(strip=True)), None)
        if not next_link:
            break
        href = next_link["href"]
        if href.startswith("javascript"):
            raise ValueError("Unsupported syllabus pagination")
        time.sleep(.18)
        page = soup(session.get(urljoin(SEARCH,href),timeout=30))


def detail_metadata(session, course):
    unit, code = course["department"], course["code"]
    url = f"https://syllabus.niigata-u.ac.jp/syllabusHtml/{YEAR}/{unit}/{unit}_{code}_ja_JP.html"
    page = soup(session.get(url, timeout=20))
    cells = {}
    for label in page.select("tr > th"):
        value = label.find_next_sibling("td")
        if value:
            cells[label.get_text(strip=True).split("／")[0]] = value.get_text(" ", strip=True)
    credit_text = clean(cells.get("単位数",""))
    if not re.fullmatch(r"\d+(?:\.\d+)?", credit_text):
        raise ValueError(f"{code}: credits unavailable")
    return {"credits":float(credit_text), "fields":re.findall(r"(\d{2})\s*[:：]", cells.get("分野","")),
            "format":cells.get("授業形態",""), "category":re.split(r"[\s／]",cells.get("科目区分",""))[0], "page":None}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layout", type=Path, help="Reuse positioned text exported by pdf-layout.cjs")
    args=parser.parse_args()
    session=requests.Session()
    with (nullcontext(None) if args.layout else tempfile.TemporaryDirectory()) as temp:
        layout=args.layout or Path(temp)/"layout.json"
        if not args.layout:
            pdf=Path(temp)/"courses.pdf"
            response=session.get(LISTING,timeout=40)
            response.raise_for_status()
            pdf.write_bytes(response.content)
            subprocess.run(["node",str(ROOT/"tools/pdf-layout.cjs"),str(pdf),str(layout)],check=True)
        fields, printed=printed_metadata(json.loads(layout.read_text("utf-8")))
    courses={}
    for unit in UNITS:
        for course in get_courses(session,unit):
            code=course["code"]
            metadata = printed.get(code) or detail_metadata(session, course)
            courses[code]={**course, **metadata}
        print(unit,len(courses),flush=True)
    if len(courses)<4000 or "261G7011" not in courses:
        raise ValueError("Incomplete public syllabus index; prior catalog was preserved")
    out=ROOT/"src"/"catalog-2026.json"
    out.parent.mkdir(exist_ok=True, parents=True)
    header={"year":YEAR,"listing":LISTING,"fields":fields}
    records=",\n".join(json.dumps(courses[k],ensure_ascii=False,separators=(",",":")) for k in sorted(courses))
    output=json.dumps(header,ensure_ascii=False,separators=(",",":"))[:-1]+',"courses":[\n'+records+'\n]}\n'
    temp_file=out.with_suffix(".tmp")
    temp_file.write_text(output,encoding="utf-8",newline="\n")
    temp_file.replace(out)


if __name__ == "__main__":
    main()
