"""Update the release fields in the checked-in SideStore/AltStore source."""

import json
import os
import sys
from datetime import date
from pathlib import Path
from shutil import copymode
from tempfile import TemporaryDirectory


SOURCE = Path(__file__).resolve().parents[1] / "distribution/altstore-source.json"


def fail(message: str, status: int) -> int:
    print(message, file=sys.stderr)
    return status


def pubspec_version() -> str:
    with Path("pubspec.yaml").open(encoding="utf-8") as pubspec:
        for line in pubspec:
            if line.startswith("version:"):
                return next(iter(line.split()[1:2]), "")
    return ""


def write_utf8(path: Path, data: str) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(data)


def write_source(output: Path, source: dict) -> None:
    data = json.dumps(source, ensure_ascii=False, indent=2) + "\n"
    destination = output.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and not destination.is_file():
        write_utf8(destination, data)
        return
    with TemporaryDirectory(dir=destination.parent) as directory:
        temporary = Path(directory) / destination.name
        write_utf8(temporary, data)
        if destination.exists():
            copymode(destination, temporary)
        temporary.replace(destination)


def main() -> int:
    if len(sys.argv) != 2:
        return fail("Usage: generate_altstore_source.sh path/to/MoreBetterGakujo-vX.Y.Z.ipa", 64)
    ipa = Path(sys.argv[1])
    if not ipa.is_file():
        return fail(f"IPA not found: {sys.argv[1]}", 66)

    try:
        supplied_version = os.environ.get("PUBSPEC_VERSION") or pubspec_version()
    except OSError as error:
        return fail(str(error), 2)
    version, separator, build = supplied_version.partition("+")
    if not separator:
        return fail("pubspec.yaml version must include a build number, for example 0.66.0+66", 65)
    build = build.rsplit("+", 1)[-1]

    tag = os.environ.get("RELEASE_TAG") or f"v{version}"
    default_url = (
        f"https://github.com/terudoru/gakujo-chan-extender/releases/download/"
        f"{tag}/MoreBetterGakujo-{tag}.ipa"
    )
    output = os.environ.get("OUTPUT_PATH") or "distribution/altstore-source.json"
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    app, = source["apps"]
    release, = app["versions"]
    release.update(
        version=version,
        buildVersion=build,
        marketingVersion=f"{version} ({build})",
        date=os.environ.get("RELEASE_DATE") or date.today().isoformat(),
        localizedDescription=os.environ.get("RELEASE_NOTES") or "iOS/iPadOS self-signed build.",
        downloadURL=os.environ.get("DOWNLOAD_URL") or default_url,
        size=ipa.lstat().st_size,
    )
    write_source(Path(output), source)
    sys.stdout.reconfigure(errors="backslashreplace")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
