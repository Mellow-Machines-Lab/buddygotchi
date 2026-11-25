"""Indexed pixel and native RGB565 screenshots share one header."""
import base64
import struct
import sys
import unittest
import zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from boopctl_lib.device import Link, DeviceError
from boopctl_lib.image import to_image

class ShotLink(Link):
    name = 'fixture'
    def __init__(self, raw, size):
        super().__init__()
        self.raw, self.size = raw, size
    def send(self, message):
        assert message == {'t': 'dbg.shot'}
    def wait_for(self, predicate, timeout):
        return {'t': 'dbg.shot', 'w': self.size[0], 'h': self.size[1],
                'bytes': len(self.raw), 'crc': zlib.crc32(self.raw)}
    def read_line(self, deadline):
        return base64.b64encode(self.raw)

class RGB565Tests(unittest.TestCase):
    def test_native_colors_and_endianness(self):
        shot = ShotLink(struct.pack('<4H', 0xF800, 0x07E0, 0x001F, 0xFFFF), (2,2))._shot()
        self.assertIsNone(shot[0])
        self.assertEqual(list(to_image(shot).getdata()), [(255,0,0),(0,255,0),(0,0,255),(255,255,255)])
    def test_indexed_pixel_is_unchanged(self):
        raw = struct.pack('<256H', 0x001F, *([0]*255)) + bytes(4)
        shot = ShotLink(raw, (2,2))._shot()
        self.assertEqual(len(shot[0]), 256)
        self.assertEqual(to_image(shot).getpixel((1,1)), (0,0,255))
    def test_bad_length_is_rejected(self):
        with self.assertRaises(DeviceError): ShotLink(bytes(7),(2,2))._shot()
    def test_the_same_picture_again_is_not_decoded(self):
        link = ShotLink(struct.pack('<4H', 1, 2, 3, 4), (2,2))
        self.assertIsNotNone(link.shot())
        self.assertEqual(link.shot_crc, zlib.crc32(link.raw))
        self.assertIsNone(link.shot(unless=link.shot_crc), 'the dash face draws only a changed frame')
        self.assertIsNotNone(link.shot(unless=link.shot_crc ^ 1))
