"""Collect undergraduate offering identities from Niigata's public syllabus search.

python archive_index.py CACHE_DIR YEAR [YEAR ...]
The temporary cache contains public course facts only. No student inputs are used.
Requires requests and lxml. Refresh a year by using an empty cache directory.
"""
import argparse
import json
from pathlib import Path
import re
import time
import unicodedata
from urllib.parse import urljoin

from lxml import html
import requests

from build_catalog import SEARCH, UNITS

REFER = re.compile(r"return refer\('(\d{4})','([0-9A-Z]{2})','([0-9A-Z]+)',\s*'(ja_JP|)'\);")


def clean(value):
    return " ".join(unicodedata.normalize("NFKC", value).split())


def document(response):
    response.raise_for_status()
    return html.fromstring(response.content.decode("utf-8"))


def query(session, year, params):
    time.sleep(.12)
    form, = document(session.get(SEARCH, timeout=25)).xpath("//form[@name='KeywordForm']")
    values = {x.get("name"): x.get("value", "") for x in
              form.xpath(".//input[@name and @type!='button'] | .//select[@name]")}
    values.update(nendo=year, _displayCount="200", **params)
    page = document(session.post(urljoin(SEARCH, form.get("action")), data=values, timeout=30))
    contents = page.text_content()
    if "最大表示件数" in contents:
        if "jikanwariShozokuCode" not in params:
            split, options = "jikanwariShozokuCode", UNITS
        else:
            split = next((k for k in ["kaikoKubunCode", "bunya"] if k not in params), None)
            if not split:
                raise ValueError(f"Cannot subdivide {year} {params}")
            options = form.xpath(f".//select[@name='{split}']/option[@value!='']/@value")
        return [r for value in options for r in query(session, year, {**params, split:value})]
    if "該当する開講科目は存在しません" in contents:
        return []
    result = []
    page_count = 0
    while True:
        summary = re.search(r"([0-9]+)～([0-9]+)/([0-9]+)件表示", page.text_content())
        if not summary or int(summary[1]) != page_count + 1:
            raise ValueError(f"Unexpected result page for {year} {params}")
        page_count = int(summary[2])
        for button in page.xpath("//input[@value='和文' and @onclick]"):
            ref = REFER.fullmatch(button.get("onclick").strip())
            cols = [clean(col.text_content()) for col in button.xpath("ancestor::tr[1]/td")]
            if not ref or len(cols) != 8 or ref[1] != year or ref[3] != cols[4]:
                raise ValueError(f"Offering identity mismatch in {year} {params}")
            if ref[2] in UNITS:
                if "jikanwariShozokuCode" in params and ref[2] != params["jikanwariShozokuCode"]:
                    raise ValueError(f"Offering department mismatch in {year} {params}")
                row = [ref[2], cols[4], cols[5], cols[2], cols[3]]
                if not ref[4] or button.get("disabled") is not None:
                    row.append("index")
                result.append(row)
        if page_count == int(summary[3]):
            return result
        href, = page.xpath("//a[contains(.,'次へ')]/@href")
        if not href.startswith("/campus-sy/"):
            raise ValueError("Unexpected pagination URL")
        time.sleep(.12)
        page = document(session.get(urljoin(SEARCH, href), timeout=30))


def retry_query(session, year, params):
    for attempt in range(4):
        try:
            return query(session, year, params)
        except (ValueError, requests.RequestException):
            if attempt == 3:
                raise
            time.sleep(1 + attempt)


def cached_query(cache, session, year, key, value):
    path = cache / f"{year}-{key}-{value}.json"
    if path.exists():
        return json.loads(path.read_text("utf-8"))
    rows = retry_query(session, year, {key: value})
    path.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("years", nargs="+")
    parser.add_argument("--dimension", choices=["departments", "fields", "categories"], default="departments")
    args = parser.parse_args()
    args.cache.mkdir(exist_ok=True, parents=True)
    with requests.Session() as session:
        key = {"departments":"jikanwariShozokuCode", "fields":"bunya", "categories":"saikbn"}[args.dimension]
        form = document(session.get(SEARCH, timeout=25))
        values = UNITS if args.dimension == "departments" else form.xpath(
            f"//select[@name='{key}']/option[@value!='']/@value")
        for year in args.years:
            if not re.fullmatch(r"\d{4}", year):
                raise ValueError("Use a four-digit academic year")
            for value in values:
                results = cached_query(args.cache, session, year, key, value)
                print(year, key, value, len(results), flush=True)


if __name__ == "__main__":
    main()
