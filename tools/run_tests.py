#!/usr/bin/env python3
"""Run Veribeat's simulations from one maintained RTL source list."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DESIGN_SOURCES = (
    'veribeat.v', 'clock.v', 'vga.v', 'keypad.v', 'game_session.v', 'audio.v',
    'notes.v', 'song_library.v', 'control.v', 'tile_mask.v', 'event_counter.v',
    'combo_score.v', 'display.v', 'menu_display.v',
)
# The final two fields describe parameter overrides, keeping song cases visible.
TESTS = {
    name: (name, f'tests/{name}.v', []) for name in (
        'clock_tb', 'vga_tb', 'keypad_tb', 'session_tb', 'chart_sizes_tb',
        'hit_timing_tb', 'stats_counter_tb', 'combo_score_tb', 'game_tb', 'menu_display_tb',
    )
}
TESTS['menu_vga_home'] = ('menu_vga_tb', 'tests/menu_vga_tb.v', [])
TESTS['menu_vga_hud'] = ('menu_vga_tb', 'tests/menu_vga_tb.v', ['-Pmenu_vga_tb.HUD=1'])
for song in range(3):
    TESTS[f'integration_song_{song}'] = (
        'integration_tb', 'tests/integration_tb.v', [f'-Pintegration_tb.SONG_ID={song}'],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tests', nargs='*', help='Test names; omitted to run the full suite')
    parser.add_argument('--simulator-dir', type=Path, help='Directory containing iverilog and vvp')
    args = parser.parse_args()
    selected = args.tests or list(TESTS)
    for name in selected:
        if name not in TESTS:
            parser.error(f'unknown test {name}; choose from {", ".join(TESTS)}')
    executables = {}
    for name in ('iverilog', 'vvp'):
        executable = str(args.simulator_dir.resolve()/name) if args.simulator_dir else shutil.which(name)
        if not executable or not Path(executable).is_file():
            parser.error(f'{name} is required; install Icarus Verilog or pass --simulator-dir')
        executables[name] = executable
    subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix='veribeat-tests-') as directory:
        for name in selected:
            module, source, overrides = TESTS[name]
            output = str(Path(directory)/name)
            print(f'Running {name}', flush=True)
            subprocess.run([
                executables['iverilog'], '-g2005', '-Wall', '-I', str(ROOT), '-s', module,
                *overrides, '-o', output, *DESIGN_SOURCES, source,
            ], cwd=ROOT, check=True)
            subprocess.run([executables['vvp'], '-N', output], cwd=ROOT, check=True)
    print(f'PASS: Python checks and {len(selected)} simulations', flush=True)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
