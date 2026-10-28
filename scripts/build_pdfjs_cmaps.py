"""Build PDF.js viewer assets from the verified pdfjs-dist 3.11.174 archive."""

import base64
import hashlib
import json
import pathlib
import re
import sys
import tarfile

EXPECTED_SHA512 = (
    "TdTZPf1trZ8/UFu5Cx/GXB7GZM30LT+wWUNfsi6Bq8ePLnb+"
    "woNKtDymI2mxZYBpMbonNFqKmiz684DIfnd8dA=="
)
ROOT = pathlib.Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/js/upload_compression"


def main():
    archive = pathlib.Path(sys.argv[1])
    digest = base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
    if digest != EXPECTED_SHA512:
        raise SystemExit("Unexpected pdfjs-dist archive digest")
    with tarfile.open(archive, "r:gz") as tar:
        maps = {}
        for entry in tar.getmembers():
            path = pathlib.PurePosixPath(entry.name)
            if path.parent == pathlib.PurePosixPath("package/cmaps") and path.suffix == ".bcmap":
                if not entry.isfile():
                    raise SystemExit("Unexpected non-file CMap")
                maps[path.stem] = base64.b64encode(tar.extractfile(entry).read()).decode()
        if len(maps) != 168:
            raise SystemExit("Unexpected CMap count")
        license_data = tar.extractfile("package/cmaps/LICENSE").read()
        viewer = tar.extractfile("package/web/pdf_viewer.js").read()
        viewer = b"\n".join(
            line.rstrip(b" \t") if line.startswith(b"/******/") else line
            for line in viewer.splitlines()
            if not line.startswith(b"//# sourceMappingURL=")
        ) + b"\n"
        css = tar.extractfile("package/web/pdf_viewer.css").read().decode("utf-8")
        images = {
            pathlib.PurePosixPath(member.name).name: base64.b64encode(
                tar.extractfile(member).read()
            ).decode()
            for member in tar.getmembers()
            if member.isfile() and member.name.startswith("package/web/images/")
        }
        fonts = {
            pathlib.PurePosixPath(member.name).name: base64.b64encode(
                tar.extractfile(member).read()
            ).decode()
            for member in tar.getmembers()
            if member.isfile()
            and member.name.startswith("package/standard_fonts/")
            and member.name.endswith((".pfb", ".ttf"))
        }
        licenses = {
            name: tar.extractfile("package/standard_fonts/" + name).read()
            for name in ("LICENSE_FOXIT", "LICENSE_LIBERATION")
        }
    output = json.dumps(maps, sort_keys=True, separators=(",", ":")) + "\n"
    (DEST / "pdf-cmaps.json").write_bytes(output.encode("utf-8"))
    (DEST / "LICENSE.pdfjs-cmaps").write_bytes(
        b"\n".join(line.rstrip() for line in license_data.splitlines()) + b"\n"
    )
    # Keep decorative viewer resources local; missing editor-only icons are
    # removed rather than resolved against the CampusSquare page origin.
    def image_url(match):
        name = match.group(1)
        if name not in images:
            return 'url("data:,")'
        mime = "image/gif" if name.endswith(".gif") else "image/svg+xml"
        return 'url("data:' + mime + ';base64,' + images[name] + '")'

    css = re.sub(r'url\(["\']?images/([^"\')]+)["\']?\)', image_url, css)
    (DEST / "pdf_viewer.js").write_bytes(viewer)
    (DEST / "pdf_viewer.css").write_bytes(css.encode("utf-8"))
    (DEST / "pdf-standard-fonts.json").write_bytes(
        (json.dumps(fonts, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    )
    for name, contents in licenses.items():
        (DEST / ("LICENSE.pdfjs-" + name.lower())).write_bytes(
            b"\n".join(line.rstrip() for line in contents.splitlines()).rstrip(b"\n") + b"\n"
        )


if __name__ == "__main__":
    main()
