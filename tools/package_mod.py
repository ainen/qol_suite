#!/usr/bin/env python3
"""Build the canonical, installable QoL Suite release archive."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import zipfile


EXCLUDED_DIRS = {".git", ".github", ".modkit", "tests", "__pycache__"}
EXCLUDED_FILES = {
    ".gitattributes",
    ".gitignore",
    ".luarc.json",
    ".modkitignore",
}
FORBIDDEN_SUFFIXES = {".gb", ".gbc", ".gba", ".sav", ".srm"}
FORBIDDEN_MARKERS = {"caught_ball.png", "caught_marker.png"}
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def included(relative: Path) -> bool:
    if any(part in EXCLUDED_DIRS for part in relative.parts):
        return False
    if relative.name in EXCLUDED_FILES:
        return False
    return True


def zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    return info


def build(source: Path, readme: Path, output: Path, version: str) -> str:
    source = source.resolve()
    readme = readme.resolve()
    output = output.resolve()
    manifest_path = source / "manifest.json"
    if not SEMVER.fullmatch(version):
        raise SystemExit("version must use X.Y.Z")
    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not readme.is_file():
        raise SystemExit(f"missing README: {readme}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("id") != "qol_suite":
        raise SystemExit("manifest id must be qol_suite")
    manifest["version"] = version
    manifest_bytes = (
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    ).encode("utf-8")

    entries: dict[str, bytes] = {"README.md": readme.read_bytes()}
    for path in sorted(source.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"refusing to package symbolic link: {path}")
        if not path.is_file():
            continue
        if path.resolve() == output:
            continue
        relative = path.relative_to(source)
        if not included(relative):
            continue
        name = PurePosixPath(relative).as_posix()
        if name == "README.md":
            continue
        if relative.suffix.lower() in FORBIDDEN_SUFFIXES:
            raise SystemExit(f"refusing to package ROM file: {relative}")
        if relative.name.lower() in FORBIDDEN_MARKERS:
            raise SystemExit(f"refusing to package marker graphic: {relative}")
        entries[name] = manifest_bytes if name == "manifest.json" else path.read_bytes()

    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(entries):
            archive.writestr(zip_info(name), entries[name])

    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        required = {"manifest.json", "main.lua", "README.md", "LICENSE"}
        missing = sorted(required - names)
        if missing:
            raise SystemExit("archive is missing: " + ", ".join(missing))
        if any(name.startswith("tests/") for name in names):
            raise SystemExit("archive unexpectedly contains tests")
        packed = json.loads(archive.read("manifest.json"))
        if packed.get("version") != version:
            raise SystemExit("packed manifest version mismatch")

    digest = hashlib.sha256(output.read_bytes()).hexdigest().upper()
    print(f"built {output} ({len(entries)} files)")
    print(f"SHA-256 {digest}")
    return digest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("qol_suite"))
    parser.add_argument("--readme", type=Path, default=Path("README.md"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    build(args.source, args.readme, args.output, args.version)


if __name__ == "__main__":
    main()
