#!/usr/bin/env python3
"""Validate generated release metadata before uploading an update."""
import argparse
import base64
import json
from pathlib import Path
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ET.register_namespace("sparkle", SPARKLE[1:-1])


def item_version(item):
    enclosure = item.find("enclosure")
    return item.findtext(SPARKLE + "version") or (
        enclosure.get(SPARKLE + "version") if enclosure is not None else None
    )


def check_previous(feed, build):
    versions = [item_version(item) for item in ET.parse(feed).findall("./channel/item")]
    if any(not value or not value.isascii() or not value.isdigit() for value in versions):
        raise ValueError("The previous feed has a non-integer build number; review it manually.")
    if versions and build <= max(map(int, versions)):
        raise ValueError("BUILD_NUMBER must be greater than every build in the published feed.")


def merge_previous(feed, previous):
    """Retain three releases per OS/hardware branch without downloading old app ZIPs.

    This changes the feed bytes: the caller MUST re-sign the output afterwards.
    """
    tree = ET.parse(feed)
    channel = tree.find("channel")
    if channel is None:
        raise ValueError("The new feed has no channel.")
    items = {item_version(item): item for item in channel.findall("item")}
    for item in ET.parse(previous).findall("./channel/item"):
        items.setdefault(item_version(item), item)
    if any(not value or not value.isascii() or not value.isdigit() for value in items):
        raise ValueError("Cannot merge non-integer build numbers.")
    for item in channel.findall("item"):
        channel.remove(item)
    groups = {}
    for version in sorted(items, key=int, reverse=True):
        item = items[version]
        group = tuple(item.findtext(SPARKLE + field) for field in (
            "minimumSystemVersion", "maximumSystemVersion", "hardwareRequirements", "channel"
        ))
        groups[group] = groups.get(group, 0) + 1
        if groups[group] <= 3:
            channel.append(item)
    tree.write(feed, encoding="utf-8", xml_declaration=True)


def validate_appcast(feed, archive, version, build, download_url):
    items = [item for item in ET.parse(feed).findall("./channel/item") if item_version(item) == str(build)]
    if len(items) != 1:
        raise ValueError("The appcast must contain exactly one item for the new build.")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None or enclosure.get("url") != download_url:
        raise ValueError("The new update must use its immutable GitHub release download URL.")
    if enclosure.get("length") != str(Path(archive).stat().st_size):
        raise ValueError("The appcast length does not match the final archive.")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("The update needs an Ed25519 signature.")
    short_version = item.findtext(SPARKLE + "shortVersionString") or enclosure.get(SPARKLE + "shortVersionString")
    if short_version != version:
        raise ValueError("The appcast display version does not match the release.")
    if not item.findtext(SPARKLE + "minimumSystemVersion"):
        raise ValueError("The appcast must specify the minimum macOS version.")
    return {"version": version, "build": build, "archive": Path(archive).name,
            "downloadURL": download_url, "signature": signature}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    previous = commands.add_parser("check-previous")
    previous.add_argument("feed", type=Path)
    previous.add_argument("build", type=int)
    merge = commands.add_parser("merge-previous")
    merge.add_argument("feed", type=Path)
    merge.add_argument("previous", type=Path)
    verify = commands.add_parser("verify")
    verify.add_argument("feed", type=Path)
    verify.add_argument("archive", type=Path)
    verify.add_argument("version")
    verify.add_argument("build", type=int)
    verify.add_argument("download_url")
    args = parser.parse_args()
    try:
        if args.command == "check-previous":
            check_previous(args.feed, args.build)
        elif args.command == "merge-previous":
            merge_previous(args.feed, args.previous)
        else:
            print(json.dumps(validate_appcast(args.feed, args.archive, args.version, args.build, args.download_url), indent=2))
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f"Release validation failed: {error}\n")


if __name__ == "__main__":
    main()
