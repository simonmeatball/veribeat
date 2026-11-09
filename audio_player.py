#!/usr/bin/env python3
"""
audio_player.py - laptop side of the veribeat audio link.

Listens on the Basys 3 USB-UART for one-byte commands from the FPGA (audio.v)
and controls audio playback:

    FPGA -> PC   'L' <'0'..'9'>  load song N      (we reply 'K', or 'E' on error)
                 'P'             play from start
                 'S'             stop
                 'H'             hold (pause)
                 'R'             resume

Songs are looked up as songs/song_<N>.wav (also .ogg / .mp3). If a song file
is missing, a test track is generated instead: a beep on every beat at 120 BPM
(pitch depends on N), which is handy for checking audio/visual sync.

Usage:
    python3 audio_player.py                 # auto-detect the Basys 3 port
    python3 audio_player.py --list          # list serial ports
    python3 audio_player.py --port /dev/cu.usbserial-XXXXXXXX1
    python3 audio_player.py --keyboard      # no FPGA: type commands (e.g. L3, P, S)

Requirements:
    pip3 install pyserial            (required)
    pip3 install pygame-ce           (recommended; otherwise macOS 'afplay' is used)
"""

import argparse
import math
import os
import shutil
import signal
import struct
import subprocess
import sys
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SONG_DIR = os.path.join(HERE, "songs")
SONG_EXTS = (".wav", ".ogg", ".mp3")
T0 = time.monotonic()


def log(msg):
    print(f"[{(time.monotonic() - T0) * 1000:9.1f} ms] {msg}", flush=True)


# --------------------------------------------------------------------------- #
# Audio backends
# --------------------------------------------------------------------------- #
class PygameBackend:
    name = "pygame"

    def __init__(self):
        import pygame  # works for both 'pygame' and 'pygame-ce'
        pygame.mixer.pre_init(44100, -16, 2, 512)  # small buffer = low latency
        pygame.mixer.init()
        self.music = pygame.mixer.music

    def load(self, path):
        self.music.load(path)

    def play(self):
        self.music.play()

    def stop(self):
        self.music.stop()

    def pause(self):
        self.music.pause()

    def resume(self):
        self.music.unpause()


class AfplayBackend:
    """macOS fallback: runs 'afplay' and pauses it with SIGSTOP/SIGCONT."""
    name = "afplay (macOS)"

    def __init__(self):
        if not shutil.which("afplay"):
            raise RuntimeError("afplay not found")
        self.path = None
        self.proc = None

    def load(self, path):
        self.stop()
        self.path = path

    def play(self):
        self.stop()
        if self.path:
            self.proc = subprocess.Popen(["afplay", self.path])

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGCONT)  # in case it was paused
            self.proc.terminate()
            self.proc.wait()
        self.proc = None

    def pause(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGSTOP)

    def resume(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGCONT)


def make_backend():
    try:
        return PygameBackend()
    except Exception as e:  # ImportError or mixer init failure
        log(f"pygame unavailable ({e.__class__.__name__}: {e}); trying afplay")
    try:
        return AfplayBackend()
    except Exception:
        sys.exit("No audio backend. Install one with:  pip3 install pygame-ce")


# --------------------------------------------------------------------------- #
# Songs
# --------------------------------------------------------------------------- #
def make_test_track(path, song_id, seconds=30, bpm=120, rate=44100):
    """Beep on every beat; first beat of each bar is higher. Pitch set by id."""
    base = 440.0 * 2 ** (song_id / 12.0)
    beat = 60.0 / bpm
    beep_len = 0.08
    frames = bytearray()
    for n in range(int(seconds * rate)):
        t = n / rate
        beat_idx = int(t / beat)
        tb = t - beat_idx * beat
        sample = 0.0
        if tb < beep_len:
            freq = base * (2 if beat_idx % 4 == 0 else 1)
            env = 1.0 - tb / beep_len
            sample = 0.5 * env * math.sin(2 * math.pi * freq * tb)
        frames += struct.pack("<h", int(sample * 32767))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def find_song(song_dir, song_id):
    for ext in SONG_EXTS:
        p = os.path.join(song_dir, f"song_{song_id}{ext}")
        if os.path.isfile(p):
            return p
    p = os.path.join(song_dir, f"test_{song_id}.wav")
    if not os.path.isfile(p):
        log(f"song_{song_id} not found, generating test track {p}")
        make_test_track(p, song_id)
    return p


# --------------------------------------------------------------------------- #
# Command handling
# --------------------------------------------------------------------------- #
class Controller:
    def __init__(self, backend, song_dir, send):
        self.backend = backend
        self.song_dir = song_dir
        self.send = send          # function(bytes) -> reply to FPGA
        self.expect_id = False    # True right after an 'L'

    def handle(self, byte):
        ch = chr(byte) if 32 <= byte < 127 else f"0x{byte:02x}"

        if self.expect_id:
            self.expect_id = False
            if not (ord("0") <= byte <= ord("9")):
                log(f"LOAD: bad song id {ch!r}  -> reply 'E'")
                self.send(b"E")
                return
            song_id = byte - ord("0")
            try:
                path = find_song(self.song_dir, song_id)
                self.backend.load(path)
                shown = os.path.relpath(path, HERE) if path.startswith(HERE) else path
                log(f"LOAD song {song_id}: {shown}  -> reply 'K'")
                self.send(b"K")
            except Exception as e:
                log(f"LOAD song {song_id} failed: {e}  -> reply 'E'")
                self.send(b"E")
            return

        if ch == "L":
            self.expect_id = True
        elif ch == "P":
            self.backend.play()
            log("PLAY")
        elif ch == "S":
            self.backend.stop()
            log("STOP")
        elif ch == "H":
            self.backend.pause()
            log("PAUSE")
        elif ch == "R":
            self.backend.resume()
            log("RESUME")
        else:
            log(f"unknown byte {ch!r} (ignored)")


# --------------------------------------------------------------------------- #
# Serial port helpers
# --------------------------------------------------------------------------- #
def list_ports():
    from serial.tools import list_ports as lp
    ports = list(lp.comports())
    if not ports:
        print("No serial ports found. Is the Basys 3 plugged in and powered on?")
    for p in ports:
        vid = f"{p.vid:04x}" if p.vid is not None else "----"
        print(f"  {p.device:45s} vid={vid}  {p.description}")


def auto_port():
    """The Basys 3's FTDI chip (vid 0x0403) has two channels; UART is the second.
    On macOS it is the /dev/cu.usbserial-...1 entry."""
    from serial.tools import list_ports as lp
    ftdi = [p.device for p in lp.comports()
            if p.vid == 0x0403 or "usbserial" in p.device]
    if sys.platform == "darwin":
        ftdi = [d for d in ftdi if d.startswith("/dev/cu.")]
    if not ftdi:
        return None
    ftdi.sort()
    ending_in_1 = [d for d in ftdi if d.endswith("1")]
    return ending_in_1[-1] if ending_in_1 else ftdi[-1]


# --------------------------------------------------------------------------- #
# Main loops
# --------------------------------------------------------------------------- #
def run_serial(args, backend):
    import serial

    port = args.port or auto_port()
    if not port:
        list_ports()
        sys.exit("Could not find the Basys 3 UART. Pass --port explicitly.")

    try:
        ser = serial.Serial(port, args.baud, timeout=0.01)
    except serial.SerialException as e:
        sys.exit(f"Could not open {port}: {e}\n"
                 "(Close any other program using the port, e.g. screen.)")

    ser.reset_input_buffer()
    log(f"listening on {port} @ {args.baud} baud, backend = {backend.name}")
    log("press buttons on the Basys 3 (Ctrl-C to quit)")

    def send(data):
        ser.write(data)
        ser.flush()

    ctl = Controller(backend, args.songs, send)
    try:
        while True:
            data = ser.read(64)
            for b in data:
                ctl.handle(b)
    except KeyboardInterrupt:
        pass
    finally:
        backend.stop()
        ser.close()


def run_keyboard(args, backend):
    """No FPGA: type the bytes the FPGA would send, e.g. 'L3', 'P', 'H', 'R', 'S'."""
    log(f"keyboard mode, backend = {backend.name}")
    print("Type commands like L3, P, H, R, S (Enter after each). Ctrl-D to quit.")
    ctl = Controller(backend, args.songs,
                     lambda d: log(f"   (would send {d.decode()!r} to FPGA)"))
    try:
        for line in sys.stdin:
            for c in line.strip().upper():
                ctl.handle(ord(c))
    except KeyboardInterrupt:
        pass
    finally:
        backend.stop()


def main():
    ap = argparse.ArgumentParser(description="veribeat audio player (UART <-> Basys 3)")
    ap.add_argument("--port", help="serial port (default: auto-detect Basys 3)")
    ap.add_argument("--baud", type=int, default=115200, help="must match audio.v (default 115200)")
    ap.add_argument("--songs", default=DEFAULT_SONG_DIR, help="folder with song_<N>.wav files")
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--keyboard", action="store_true", help="test without the FPGA")
    args = ap.parse_args()

    if args.list:
        list_ports()
        return

    backend = make_backend()
    if args.keyboard:
        run_keyboard(args, backend)
    else:
        run_serial(args, backend)


if __name__ == "__main__":
    main()
