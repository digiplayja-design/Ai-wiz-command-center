#!/usr/bin/env python3
"""Rebuild the approved welcome mix; developer-only, never run by the app.

Requires Python, NumPy and FFmpeg. Inputs and licensing are documented in
assets/onboarding/README.md. The approved narration is preserved in full.
"""

import argparse
import hashlib
import json
import math
import subprocess
import wave
from pathlib import Path

import numpy as np


VOICE_SHA256 = "d1e6aff7432f5cca5a7f6a0ddf3a4eb6b4dbc97ebefed398a3f689607120050c"
MUSIC_SHA256 = "50e3306a36eabead31dc702bb7654ff935351d19b9ef40421e89b4e037f92bb9"
RATE = 24000
VOICE_LEAD_SECONDS = 1.5
MUSIC_TAIL_SECONDS = 0.5
MUSIC_OFFSET_SECONDS = 32


def rms(samples):
    return float(np.sqrt(np.mean(np.square(samples))))


def db(value):
    return 20 * math.log10(max(value, 1e-12))


def checked_file(path, expected):
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(f"Unexpected source recording: {path.name}")


def mix(voice_path, music_path, output_path):
    checked_file(voice_path, VOICE_SHA256)
    checked_file(music_path, MUSIC_SHA256)
    with wave.open(str(voice_path), "rb") as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, RATE):
            raise ValueError("Narration must be 24 kHz mono PCM16")
        narration = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64) / 32768
    # Establish the music before the first word. Keep every narration sample,
    # with a short music tail after the final word.
    lead = round(VOICE_LEAD_SECONDS * RATE)
    tail = round(MUSIC_TAIL_SECONDS * RATE)
    voice = np.pad(narration, (lead, tail))
    length = len(voice)
    duration = length / RATE
    decoded = subprocess.check_output([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(MUSIC_OFFSET_SECONDS),
        "-i", str(music_path),
        "-t", str(duration), "-ac", "1", "-ar", str(RATE),
        "-af", "highpass=f=120,lowpass=f=9000", "-f", "f32le", "pipe:1",
    ])
    music = np.frombuffer(decoded, dtype="<f4").astype(np.float64)
    if len(music) < length:
        raise ValueError("The selected music excerpt is shorter than the narration")
    music = music[:length]

    # Detect speech in 20 ms frames. Look ahead 60 ms and hold 120 ms, so
    # the music softens before words and does not pump between syllables.
    frame = RATE // 50
    energy = np.array([rms(voice[i:i + frame]) for i in range(0, length, frame)])
    speech = energy > 0.015
    active = np.repeat(speech, frame)[:length]
    held = np.array([speech[max(0, i - 6):i + 4].any() for i in range(len(speech))])
    envelope = np.empty(len(held))
    speech_gain = 10 ** (-3 / 20)
    gain = 1.0
    for i, speaking in enumerate(held):
        target = speech_gain if speaking else 1.0
        seconds = 0.02 if target < gain else 0.30
        gain += (target - gain) * (1 - math.exp(-0.02 / seconds))
        envelope[i] = gain
    ducking = np.interp(np.arange(length), np.arange(len(envelope)) * frame, envelope)

    # Use a fuller section of the track at a clearly audible level: 4 dB
    # below active speech before ducking, with just 3 dB of speech ducking.
    music *= (rms(voice[active]) * 10 ** (-4 / 20)) / rms(music[active])
    music *= ducking
    fade_in = min(length, round(0.15 * RATE))
    fade_out = min(length, round(0.75 * RATE))
    music[:fade_in] *= np.sin(np.linspace(0, math.pi / 2, fade_in)) ** 2
    music[-fade_out:] *= np.cos(np.linspace(0, math.pi / 2, fade_out)) ** 2
    mixed = voice + music
    # Preserve headroom without clipping or compressing the narrator.
    master = min(1.0, 10 ** (-1.5 / 20) / np.max(np.abs(mixed)))
    pcm = np.rint(mixed * master * 32767).astype("<i2")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())

    report = {
        "duration_seconds": duration,
        "sample_rate": RATE,
        "samples": length,
        "bytes": output_path.stat().st_size,
        "sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(),
        "music_excerpt_start_seconds": MUSIC_OFFSET_SECONDS,
        "narration_duration_seconds": len(narration) / RATE,
        "narration_start_seconds": VOICE_LEAD_SECONDS,
        "music_tail_seconds": MUSIC_TAIL_SECONDS,
        "music_below_active_voice_db": round(db(rms(voice[active]) / rms(music[active])), 2),
        "music_opening_rms_dbfs": round(db(rms(music[:lead] * master)), 2),
        "master_gain_db": round(db(master), 2),
        "sample_peak_dbfs": round(db(float(np.max(np.abs(pcm.astype(float)))) / 32768), 2),
        "clipped_samples": int(np.count_nonzero(np.abs(pcm.astype(np.int32)) >= 32767)),
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("voice", type=Path)
    parser.add_argument("music", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.resolve() in (args.voice.resolve(), args.music.resolve()):
        parser.error("Output must not overwrite a source recording")
    mix(args.voice, args.music, args.output)
