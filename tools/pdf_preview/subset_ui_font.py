#!/usr/bin/env python3
"""Generate the small Japanese UI font from the bundled Noto collection.

Install fonttools==4.60.1, then pass the generated localization Dart files from
the versions of material_ui and cupertino_ui recorded in pubspec.lock.
"""

import argparse
import hashlib
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'assets' / 'NotoSansCJK-Regular.ttc'
OUTPUT = HERE / 'assets' / 'MBGPreviewUI.otf'


def localization(path: Path, class_name: str) -> str:
    text = path.read_text(encoding='utf-8')
    start = text.index(f'class {class_name} ')
    end = text.find('\nclass ', start + 1)
    return text[start:end if end != -1 else None]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--material-localizations', required=True, type=Path)
    parser.add_argument('--cupertino-localizations', required=True, type=Path)
    args = parser.parse_args()
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != 'b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a':
        raise SystemExit('Unexpected Noto source font')
    text = ''.join(path.read_text(encoding='utf-8') for path in (HERE / 'lib').glob('*.dart'))
    text += localization(args.material_localizations, 'MaterialLocalizationJa')
    text += localization(args.cupertino_localizations, 'CupertinoLocalizationJa')
    characters = (set(range(0x20, 0x7f)) | set(range(0x3000, 0x3100)) |
                  set(range(0xff00, 0xfff0)) | {ord(c) for c in text if 0x3400 <= ord(c) <= 0x9fff})
    font = TTFont(SOURCE, fontNumber=0, recalcTimestamp=False)
    options = subset.Options()
    options.hinting = False
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=characters)
    subsetter.subset(font)
    names = {1: 'MBG Preview UI', 3: 'MBG Preview UI Regular',
             4: 'MBG Preview UI Regular', 6: 'MBGPreviewUI-Regular',
             16: 'MBG Preview UI', 17: 'Regular'}
    for record in font['name'].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding(), errors='replace')
    font.save(OUTPUT)


if __name__ == '__main__':
    main()
