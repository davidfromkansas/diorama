#!/usr/bin/env python3
"""Offline release-feed contract tests; signature cryptography is Sparkle's job."""
import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('feed', Path(__file__).with_name('verify-update-feed.py'))
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)

class FeedTests(unittest.TestCase):
    def test_metadata_is_bound_to_release_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Diorama-1.2.3-99-arm64.dmg').write_bytes(b'fixture')
            signature = base64.b64encode(bytes(64)).decode()
            xml = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:version>99</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                <enclosure url="https://github.com/davidfromkansas/diorama-releases/releases/download/v1.2.3/Diorama-1.2.3-99-arm64.dmg" length="7" sparkle:edSignature="{signature}"/>
                </item></channel></rss>'''
            path = root / 'appcast.xml'
            path.write_text(xml)
            feed.verify(path, root, '1.2.3', '99')
            for original, replacement in [('github.com', 'example.com'), ('length="7"', 'length="8"'), ('>99<', '>98<'), ('>1.2.3<', '>1.2.2<'), (signature, 'invalid')]:
                with self.subTest(original=original):
                    path.write_text(xml.replace(original, replacement))
                    with self.assertRaises((AssertionError, ValueError)):
                        feed.verify(path, root, '1.2.3', '99')

if __name__ == '__main__': unittest.main()
