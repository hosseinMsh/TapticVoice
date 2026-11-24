#!/usr/bin/env python3
"""
TapticVoice Neural Speech & Haptic Mastering Generator
"""

import sys
import asyncio
import subprocess
from pathlib import Path

DEFAULT_VOICE = "fa-IR-FaridNeural"
AUDIO_FILTER_HAPTIC = (
    "highpass=f=120,lowpass=f=3800,"
    "equalizer=f=1000:t=q:w=1.2:g=3.5,"
    "equalizer=f=2200:t=q:w=1.2:g=4.0,"
    "compand=attacks=0.02:decays=0.1:points=-60/-60|-20/-6|0/-1:gain=2"
)

async def _synthesize_edge_tts(text: str, output_mp3: Path, rate: str, pitch: str):
    import edge_tts
    communicate = edge_tts.Communicate(text, DEFAULT_VOICE, rate=rate, pitch=pitch)
    await communicate.save(str(output_mp3))

def main():
    if len(sys.argv) < 3:
        print("Usage: taptic_synth.py <output_wav> <text> [speed_pct] [pitch_hz]")
        sys.exit(1)

    target_wav = Path(sys.argv[1]).resolve()
    text = sys.argv[2]
    speed_pct = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    pitch_hz = int(sys.argv[4]) if len(sys.argv) > 4 else 0

    target_wav.parent.mkdir(parents=True, exist_ok=True)
    raw_mp3 = target_wav.with_suffix(".temp.mp3")

    rate_str = f"{speed_pct:+d}%" if speed_pct != 0 else "+0%"
    pitch_str = f"{pitch_hz:+d}Hz" if pitch_hz != 0 else "+0Hz"

    used_neural = False
    try:
        asyncio.run(_synthesize_edge_tts(text, raw_mp3, rate=rate_str, pitch=pitch_str))
        if raw_mp3.exists() and raw_mp3.stat().st_size > 0:
            used_neural = True
    except Exception as e:
        print(f"Neural TTS warning: {e}", file=sys.stderr)
        used_neural = False

    if used_neural:
        cmd_ffmpeg = [
            "/opt/homebrew/bin/ffmpeg", "-y",
            "-i", str(raw_mp3),
            "-af", AUDIO_FILTER_HAPTIC,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_f32le",
            str(target_wav)
        ]
        subprocess.run(cmd_ffmpeg, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        try:
            raw_mp3.unlink()
        except Exception:
            pass
    else:
        raw_wav = target_wav.with_suffix(".temp.wav")
        cmd_espeak = [
            "/opt/homebrew/bin/espeak-ng",
            "-v", "fa",
            "-s", str(max(80, 150 + int(speed_pct * 1.5))),
            "-p", str(max(10, 50 + int(pitch_hz * 0.8))),
            "-w", str(raw_wav),
            text
        ]
        subprocess.run(cmd_espeak, check=True)
        cmd_ffmpeg = [
            "/opt/homebrew/bin/ffmpeg", "-y",
            "-i", str(raw_wav),
            "-af", AUDIO_FILTER_HAPTIC,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_f32le",
            str(target_wav)
        ]
        subprocess.run(cmd_ffmpeg, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        try:
            raw_wav.unlink()
        except Exception:
            pass

    print(f"SUCCESS:{target_wav}")

if __name__ == "__main__":
    main()
