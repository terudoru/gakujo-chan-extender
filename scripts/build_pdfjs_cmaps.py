"""Build the bundled CMaps from the verified pdfjs-dist 3.11.174 archive."""

import base64
import hashlib
import json
import pathlib
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
    output = json.dumps(maps, sort_keys=True, separators=(",", ":")) + "\n"
    (DEST / "pdf-cmaps.json").write_bytes(output.encode("utf-8"))
    (DEST / "LICENSE.pdfjs-cmaps").write_bytes(
        b"\n".join(line.rstrip() for line in license_data.splitlines()) + b"\n"
    )


if __name__ == "__main__":
    main()
