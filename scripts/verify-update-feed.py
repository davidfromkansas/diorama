#!/usr/bin/env python3
"""Validate the feed against the exact release artifacts before publishing."""
import base64
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def verify(feed, directory, version, build):
    sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    items = ET.parse(feed).findall('./channel/item')
    assert len(items) == 1, 'Expected exactly one release in this feed'
    item = items[0]
    assert item.findtext(sparkle + 'version') == build, 'Build mismatch'
    assert item.findtext(sparkle + 'shortVersionString') == version, 'Version mismatch'
    enclosure = item.find('enclosure')
    assert enclosure is not None, 'No update enclosure'
    name = f'Diorama-{version}-{build}-arm64.dmg'
    expected = f'https://github.com/davidfromkansas/diorama-releases/releases/download/v{version}/{name}'
    assert enclosure.get('url') == expected, 'Unexpected download URL'
    assert int(enclosure.get('length', '0')) == (Path(directory) / name).stat().st_size, 'Size mismatch'
    assert len(base64.b64decode(enclosure.get(sparkle + 'edSignature', ''), validate=True)) == 64, 'Missing update signature'
    assert item.findtext(sparkle + 'minimumSystemVersion'), 'Missing OS compatibility'


if __name__ == '__main__':
    verify(*sys.argv[1:])
    print('Update feed metadata and artifact verified')
