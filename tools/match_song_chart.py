#!/usr/bin/env python3
"""Match a four-lane Veribeat chart to attacks in a particular audio file.

Optional authoring dependencies: numpy, scipy, librosa, soundfile, imageio-ffmpeg.
This tool is separate from the dependency-free TXT-to-ROM compiler.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile

import imageio_ffmpeg
import librosa
import numpy as np
from scipy.signal import find_peaks
import soundfile as sf

from compile_chart import compile_chart


SAMPLE_RATE = 22050
HOP = 256


def analyze(source):
    with tempfile.TemporaryDirectory() as directory:
        decoded = Path(directory) / 'decoded.wav'
        subprocess.run([
            imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
            '-y', '-i', str(source), '-ac', '1', '-ar', str(SAMPLE_RATE),
            '-c:a', 'pcm_s16le', str(decoded),
        ], check=True)
        audio, sample_rate = sf.read(decoded, dtype='float32')
    envelope = librosa.onset.onset_strength(y=audio, sr=sample_rate, hop_length=HOP)
    peaks, properties = find_peaks(envelope, distance=7, prominence=0.15)
    if len(peaks) < 8:
        raise ValueError('Too few clear attacks for automatic rhythm matching')
    times = peaks * HOP / sample_rate
    strength = envelope[peaks]
    weights = np.minimum(strength, np.percentile(strength, 95))
    estimate, _ = librosa.beat.beat_track(
        onset_envelope=envelope, sr=sample_rate, hop_length=HOP,
    )
    estimate = float(np.asarray(estimate).item())

    # Refine the tempo against the entire recording, avoiding cumulative
    # phase drift from estimating tempo using a rounded FFT bin alone.
    def coherence(bpm, harmonic=4):
        return np.sum(weights * np.exp(2j * np.pi * times * bpm / 60 * harmonic))

    coarse = np.arange(estimate * 0.9, estimate * 1.1, 0.05)
    best = max(coarse, key=lambda bpm: abs(coherence(bpm)))
    fine = np.arange(best - 0.06, best + 0.061, 0.001)
    tempo = float(max(fine, key=lambda bpm: abs(coherence(bpm))))
    beat_period = 60 / tempo
    eighth_period = beat_period / 2
    phase = float((np.angle(coherence(tempo, 2)) / (2*np.pi) * eighth_period) % eighth_period)

    # Use spectral brightness to shape lane choices. Attacks still determine
    # every timestamp. Lane choices are game choreography, not pitch notation.
    spectrum = np.abs(librosa.stft(audio, n_fft=2048, hop_length=HOP))
    frequencies = librosa.fft_frequencies(sr=sample_rate, n_fft=2048)
    band = (frequencies >= 100) & (frequencies <= 3000)
    brightness = np.sum(spectrum[band] * frequencies[band, None], axis=0) / np.maximum(
        np.sum(spectrum[band], axis=0), 1e-8,
    )
    local_thresholds = np.array([
        np.quantile(strength[np.abs(times-time) < 4], 0.58) for time in times
    ])
    return {
        'duration': len(audio) / sample_rate,
        'times': times, 'strength': strength, 'peaks': peaks,
        'prominence': properties['prominences'], 'threshold': local_thresholds,
        'tempo': tempo, 'period': beat_period, 'phase': phase,
        'coherence': float(abs(coherence(tempo)) / np.sum(weights)),
        'brightness': brightness, 'envelope': envelope,
    }


def select_events(analysis):
    times = analysis['times']
    strength = analysis['strength']
    selected = {}
    # Keep attacks near beats, plus the stronger intervening eighth notes.
    # Selected timestamps remain the measured attack times rather than grid ticks.
    grid = np.arange(analysis['phase'], analysis['duration'], analysis['period']/2)
    for grid_index, tick in enumerate(grid):
        nearby = np.flatnonzero(np.abs(times-tick) < 0.065)
        if not len(nearby):
            continue
        index = max(nearby, key=lambda i: strength[i] * np.exp(-0.5*((times[i]-tick)/0.04)**2))
        threshold = max(0.4, analysis['threshold'][index] * (0.6 if grid_index % 2 == 0 else 1.1))
        if strength[index] >= threshold:
            selected[int(index)] = 'beat' if grid_index % 2 == 0 else 'eighth'

    # Retain clear syncopated attacks missed by the main grid, while keeping
    # a playable gap and leaving capacity for a few accent chords.
    for index in np.argsort(-strength):
        if len(selected) >= 930:
            break
        if strength[index] < analysis['threshold'][index] * 1.25:
            continue
        if all(abs(times[index]-times[other]) >= 0.160 for other in selected):
            selected[int(index)] = 'syncopation'

    # Resolve occasional close grid matches by keeping the stronger attack.
    ordered = []
    for index in sorted(selected, key=lambda i: times[i]):
        if ordered and times[index]-times[ordered[-1]] < 0.150:
            if strength[index] > strength[ordered[-1]]:
                ordered[-1] = index
        else:
            ordered.append(index)
    if len(ordered) > 930:
        ordered = sorted(sorted(ordered, key=lambda i: strength[i], reverse=True)[:930], key=lambda i: times[i])
    return ordered, selected


def assign_lanes(analysis, ordered):
    brightness = analysis['brightness'][analysis['peaks'][ordered]]
    cuts = np.quantile(brightness, [0.25, 0.5, 0.75])
    strengths = analysis['strength'][ordered]
    chord_threshold = np.quantile(strengths, 0.92)
    notes = []
    last_press = [-10000]*4
    chord_times = []
    last_chord = -10000
    for position, index in enumerate(ordered):
        timestamp = int(round(analysis['times'][index]*1000))
        preferred = int(np.searchsorted(cuts, brightness[position]))
        available = [lane for lane in range(4) if timestamp-last_press[lane] >= 220]
        lane = min(available, key=lambda lane: (abs(lane-preferred), last_press[lane]))
        notes.append((timestamp, lane))
        last_press[lane] = timestamp
        previous_gap = timestamp-notes[-2][0] if len(notes) > 1 else 1000
        next_gap = (analysis['times'][ordered[position+1]]*1000-timestamp) if position+1 < len(ordered) else 1000
        if (strengths[position] >= chord_threshold and previous_gap >= 200 and next_gap >= 200
                and timestamp-last_chord >= 1800 and len(chord_times) < 64):
            options = [other for other in available if other != lane]
            if options:
                second = max(options, key=lambda other: abs(other-lane))
                notes.append((timestamp, second))
                last_press[second] = timestamp
                chord_times.append(timestamp)
                last_chord = timestamp
    return sorted(notes), chord_times


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('audio', type=Path)
    parser.add_argument('--chart', type=Path, default=Path('charts/song_0.txt'))
    parser.add_argument('--song-id', type=int, choices=range(10), default=0)
    args = parser.parse_args()
    analysis = analyze(args.audio)
    ordered, kinds = select_events(analysis)
    notes, chords = assign_lanes(analysis, ordered)
    if len(notes) > 1024:
        raise ValueError('Selected chart exceeds hardware capacity')
    digest = hashlib.sha256(args.audio.read_bytes()).hexdigest()
    lines = [
        '# YOASOBI - Yoru ni Kakeru',
        f'# Rhythm chart analyzed from {args.audio.as_posix()}',
        f'# MP3 SHA-256 {digest}',
        f'# Measured tempo approximately {analysis["tempo"]:.3f} BPM.',
        '# Timestamps follow detected attacks; lanes follow brightness and playable spacing.',
        '# Automated rhythm arrangement; audio_offset_ms remains a hardware calibration value.',
        f'song_id {args.song_id}',
        f'duration_ms {math.ceil(analysis["duration"]*1000)}',
        'audio_offset_ms 0', '# target_ms lane (0 F E D, left to right)',
    ]
    lines.extend(f'{time} {lane}' for time, lane in notes)
    args.chart.parent.mkdir(parents=True, exist_ok=True)
    args.chart.write_text('\n'.join(lines)+'\n')
    compile_chart(args.chart, Path('notes_data.mem'), Path('notes_config.vh'))
    event_times = np.array([analysis['times'][index] for index in ordered])
    phase = analysis['phase']
    subdivision = analysis['period']/4
    residuals = abs((event_times-phase+subdivision/2) % subdivision-subdivision/2)*1000
    lane_gaps = [b-a for lane in range(4) for a,b in zip(
        [time for time,key in notes if key == lane][:-1],
        [time for time,key in notes if key == lane][1:],
    )]
    report = {
        'source_audio': args.audio.as_posix(), 'sha256': digest,
        'method': 'decoded MP3 spectral attacks, full-track tempo/phase fit, adaptive eighth notes and syncopations',
        'sample_rate': SAMPLE_RATE, 'hop_samples': HOP,
        'decoded_duration_ms': round(analysis['duration']*1000, 3),
        'estimated_bpm': round(analysis['tempo'], 6),
        'eighth_grid_phase_ms': round(phase*1000, 3),
        'sixteenth_phase_coherence': round(analysis['coherence'], 6),
        'notes': len(notes), 'distinct_attack_times': len(ordered),
        'accent_chords': len(chords), 'first_note_ms': notes[0][0], 'last_note_ms': notes[-1][0],
        'lane_counts': [sum(key == lane for _,key in notes) for lane in range(4)],
        'minimum_same_lane_gap_ms': min(lane_gaps),
        'median_grid_residual_ms': round(float(np.median(residuals)), 3),
        'p95_grid_residual_ms': round(float(np.percentile(residuals, 95)), 3),
        'events': [
            {'time_ms': int(round(analysis['times'][i]*1000)),
             'strength': round(float(analysis['strength'][i]), 4), 'kind': kinds[i]}
            for i in ordered
        ],
        'limitations': [
            'Automatic rhythm arrangement, without manual listening verification or melody transcription.',
            'MP3 decoder/playback latency and USB audio-start delay require board calibration.',
        ],
    }
    args.chart.with_suffix('.analysis.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({key:value for key,value in report.items() if key != 'events'}, indent=2))


if __name__ == '__main__':
    main()
