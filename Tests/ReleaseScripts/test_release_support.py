import base64
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from release_support import SPARKLE, check_previous, item_version, merge_previous, validate_appcast


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.archive = Path(self.directory.name) / 'PodsBar-1.1.0.zip'
        self.archive.write_bytes(b'final stapled archive')
        self.feed = Path(self.directory.name) / 'appcast.xml'
        self.url = 'https://github.com/musaAmir/podsbar/releases/download/v1.1.0/PodsBar-1.1.0.zip'
        self.root = ET.Element('rss')
        self.channel = ET.SubElement(self.root, 'channel')
        self.item = ET.SubElement(self.channel, 'item')
        ET.SubElement(self.item, SPARKLE + 'version').text = '2'
        ET.SubElement(self.item, SPARKLE + 'shortVersionString').text = '1.1.0'
        ET.SubElement(self.item, SPARKLE + 'minimumSystemVersion').text = '14.0'
        self.enclosure = ET.SubElement(self.item, 'enclosure', {
            'url': self.url, 'length': str(self.archive.stat().st_size),
            SPARKLE + 'edSignature': base64.b64encode(bytes(64)).decode()
        })

    def write_feed(self):
        ET.ElementTree(self.root).write(self.feed, encoding='utf-8', xml_declaration=True)

    def validate(self):
        self.write_feed()
        return validate_appcast(self.feed, self.archive, '1.1.0', 2, self.url)

    def test_accepts_matching_metadata(self):
        self.assertEqual(self.validate()['build'], 2)

    def test_rejects_archive_changed_after_signing(self):
        self.archive.write_bytes(b'changed')
        with self.assertRaises(ValueError): self.validate()

    def test_rejects_wrong_download_url(self):
        self.enclosure.set('url', self.url.replace('/v1.1.0/', '/latest/'))
        with self.assertRaises(ValueError): self.validate()

    def test_rejects_missing_signature(self):
        del self.enclosure.attrib[SPARKLE + 'edSignature']
        with self.assertRaises(ValueError): self.validate()

    def test_rejects_wrong_display_version(self):
        self.item.find(SPARKLE + 'shortVersionString').text = '1.0.0'
        with self.assertRaises(ValueError): self.validate()

    def test_rejects_missing_minimum_os(self):
        self.item.remove(self.item.find(SPARKLE + 'minimumSystemVersion'))
        with self.assertRaises(ValueError): self.validate()

    def test_rejects_duplicate_build(self):
        self.channel.append(ET.fromstring(ET.tostring(self.item)))
        with self.assertRaises(ValueError): self.validate()

    def test_build_number_must_increase(self):
        self.write_feed()
        check_previous(self.feed, 3)
        for build in [1, 2]:
            with self.assertRaises(ValueError): check_previous(self.feed, build)

    def test_previous_noninteger_build_needs_manual_review(self):
        self.item.find(SPARKLE + 'version').text = '2-beta'
        self.write_feed()
        with self.assertRaises(ValueError): check_previous(self.feed, 3)

    def test_merge_retains_old_release_url_without_its_archive(self):
        self.write_feed()
        previous = Path(self.directory.name) / 'previous.xml'
        previous.write_bytes(self.feed.read_bytes())
        self.item.find(SPARKLE + 'version').text = '3'
        self.enclosure.set('url', self.url.replace('v1.1.0', 'v1.1.1'))
        self.write_feed()
        merge_previous(self.feed, previous)
        items = ET.parse(self.feed).findall('./channel/item')
        self.assertEqual([item_version(item) for item in items], ['3', '2'])
        self.assertEqual(items[1].find('enclosure').get('url'), self.url)

    def test_merge_retains_three_per_os_branch(self):
        for version in ['3', '4', '5']:
            item = ET.fromstring(ET.tostring(self.item))
            item.find(SPARKLE + 'version').text = version
            self.channel.append(item)
        self.write_feed()
        previous = Path(self.directory.name) / 'previous.xml'
        previous.write_bytes(self.feed.read_bytes())
        for item in self.channel.findall('item'): self.channel.remove(item)
        self.item.find(SPARKLE + 'version').text = '6'
        self.item.find(SPARKLE + 'minimumSystemVersion').text = '15.0'
        self.channel.append(self.item)
        self.write_feed()
        merge_previous(self.feed, previous)
        self.assertEqual([item_version(item) for item in ET.parse(self.feed).findall('./channel/item')],
                         ['6', '5', '4', '3'])


if __name__ == '__main__':
    unittest.main()
