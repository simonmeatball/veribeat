"""Chart capacity and input validation checks, using isolated outputs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('chart_compiler', Path(__file__).resolve().parents[1] / 'tools/compile_chart.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class ChartCompilerTest(unittest.TestCase):
    def compile(self, body, metadata='song_id 0\nduration_ms 100000\naudio_offset_ms 0\n'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'chart.txt'
            source.write_text(metadata + body)
            count = compiler.compile_chart(source, root/'chart.mem', root/'config.vh')
            return count, (root/'chart.mem').read_text().splitlines()

    def test_capacity_and_padding(self):
        for count in (0, 8, 1024):
            with self.subTest(count=count):
                actual, words = self.compile(''.join(f'{i*10} {i%4}\n' for i in range(count)))
                self.assertEqual(actual, count)
                self.assertEqual(len(words), 1024)
                if count:
                    self.assertEqual(int(words[count-1], 16), (1<<39) | ((count-1)*10<<2) | ((count-1)%4))
                if count < 1024:
                    self.assertEqual(int(words[count], 16), 0)

    def test_invalid_entries(self):
        for body in ('1 4\n', '-1 0\n', '2 0\n1 1\n', '2 0\n2 0\n', 'x 0\n', '1 0 extra\n',
                     ''.join(f'{i} 0\n' for i in range(1025))):
            with self.subTest(body=body[:40]), self.assertRaises(ValueError):
                self.compile(body)

    def test_chord_and_offset(self):
        count, words = self.compile('200 0\n200 3\n', 'song_id 0\nduration_ms 500\naudio_offset_ms -100\n')
        self.assertEqual(count, 2)
        self.assertEqual(int(words[0], 16), (1<<39) | (100<<2))
        self.assertEqual(int(words[1], 16), (1<<39) | (100<<2) | 3)

    def test_invalid_metadata(self):
        for metadata in ('song_id 10\nduration_ms 100\naudio_offset_ms 0\n',
                         'song_id 0\nduration_ms 0\naudio_offset_ms 0\n',
                         'song_id 0\nduration_ms 100\naudio_offset_ms -200\n',
                         'song_id 0\n'):
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                self.compile('100 0\n', metadata)


if __name__ == '__main__':
    unittest.main()
