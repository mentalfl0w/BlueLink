#!/usr/bin/env python3
"""Validate BlueLink's generated Sparkle appcast before it is published."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
FEED_URL_PREFIX = "https://github.com/mentalfl0w/BlueLink/releases/download/"
RELEASE_NOTES_URL_PREFIX = "https://github.com/mentalfl0w/BlueLink/releases/tag/"


def validate_appcast(
    *,
    path: Path,
    tag: str,
    version: str,
    build_number: str,
    archive_name: str,
) -> None:
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        raise ValueError("generated Sparkle appcast is unreadable") from error

    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("stable Sparkle appcast must contain exactly one release item")

    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Sparkle appcast item has no enclosure")

    expected_url = f"{FEED_URL_PREFIX}{tag}/{archive_name}"
    if enclosure.get("url") != expected_url:
        raise ValueError("Sparkle enclosure URL does not match the published archive")
    if not enclosure.get(f"{{{SPARKLE_NAMESPACE}}}edSignature"):
        raise ValueError("Sparkle archive signature is missing")
    length = enclosure.get("length", "0")
    if not re.fullmatch(r"[1-9][0-9]*", length):
        raise ValueError("Sparkle archive length is missing or invalid")

    sparkle_version = item.find(f"{{{SPARKLE_NAMESPACE}}}version")
    short_version = item.find(f"{{{SPARKLE_NAMESPACE}}}shortVersionString")
    if sparkle_version is None or sparkle_version.text != build_number:
        raise ValueError("Sparkle appcast build version does not match CFBundleVersion")
    if short_version is None or short_version.text != version:
        raise ValueError("Sparkle appcast short version does not match the release tag")

    release_notes_link = item.find(f"{{{SPARKLE_NAMESPACE}}}fullReleaseNotesLink")
    if release_notes_link is None or release_notes_link.text != f"{RELEASE_NOTES_URL_PREFIX}{tag}":
        raise ValueError("Sparkle release notes link does not match the GitHub release")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--archive-name", required=True)
    args = parser.parse_args()
    try:
        validate_appcast(
            path=args.path,
            tag=args.tag,
            version=args.version,
            build_number=args.build_number,
            archive_name=args.archive_name,
        )
    except ValueError as error:
        print(f"Sparkle release validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
