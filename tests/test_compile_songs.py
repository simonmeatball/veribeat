"""The menu library must publish matching banks and metadata together."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/compile_songs.py'


class SongLibraryCompilerTest(unittest.TestCase):
    def test_all_banks_and_invalid_selection_id(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            charts = root / 'charts'
            charts.mkdir()
            for song in range(3):
                (charts / f'song_{song}.txt').write_text(
                    f'song_id {song}\nduration_ms 2000\naudio_offset_ms 0\n1000 {song}\n'
                )
            result = subprocess.run([sys.executable, str(SCRIPT)], cwd=root, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            header = root / 'song_library_config.vh'
            self.assertIn('`define SONG_2_NOTE_COUNT 1', header.read_text())
            self.assertFalse(list(charts.glob("*.vh")))
            generated = [header] + list(charts.glob('*.mem')) + list(charts.glob('*.vh'))
            before = {path: path.read_bytes() for path in generated}
            source = charts / 'song_2.txt'
            source.write_text(source.read_text().replace('song_id 2', 'song_id 1'))
            failed = subprocess.run([sys.executable, str(SCRIPT)], cwd=root, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn(b'must declare song_id 2', failed.stderr)
            self.assertEqual(before, {path: path.read_bytes() for path in generated})


if __name__ == '__main__':
    unittest.main()
