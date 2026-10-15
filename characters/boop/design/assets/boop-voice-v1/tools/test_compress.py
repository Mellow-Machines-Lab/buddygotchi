import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

spec=importlib.util.spec_from_file_location('pcm8_compress',Path(__file__).with_name('compress.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)

class Compression(unittest.TestCase):
    def test_unsigned_pcm_and_source_preservation(self):
        with tempfile.TemporaryDirectory() as d:
            source,target=Path(d)/'source.wav',Path(d)/'output.wav'
            with wave.open(str(source),'wb') as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(11025)
                w.writeframes(struct.pack('<7h',-32768,-16384,-256,0,256,16384,32767))
            before=c.sha(source);c.quantize(source,target)
            with wave.open(str(target),'rb') as w:
                self.assertEqual((w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes()),(1,1,11025,7))
                self.assertEqual(list(w.readframes(7)),[0,64,127,128,129,192,255])
            self.assertEqual(before,c.sha(source))
            self.assertEqual(c.wav_stats(target)['seconds'],7/11025)

    def test_quantizer_rejects_wrong_rate(self):
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'source.wav'
            with wave.open(str(source),'wb') as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(44100);w.writeframes(b'\x00\x00')
            with self.assertRaises(AssertionError):c.quantize(source,Path(d)/'output.wav')

    def test_archive_cannot_be_inside_repo(self):
        target=c.ROOT/'not-an-archive'
        result=subprocess.run([sys.executable,str(Path(c.__file__)),'--archive',str(target)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('outside the repository',result.stderr)
        self.assertFalse(target.exists())

if __name__=='__main__':unittest.main()
