#!/usr/bin/env python3
"""
Self-contained standalone Neural Speech synthesizer helper for TapticVoice.
Outputs MP3 audio using Edge Neural TTS.
"""

import sys
import asyncio
from pathlib import Path

DEFAULT_VOICE = "fa-IR-FaridNeural"

async def main():
    if len(sys.argv) < 3:
        print("Usage: synth_cli <output_file> <text> [speed_pct] [pitch_hz]")
        sys.exit(1)

    out_file = Path(sys.argv[1]).resolve()
    text = sys.argv[2].strip()
    if not text:
        sys.exit(0)

    speed_pct = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    pitch_hz = int(sys.argv[4]) if len(sys.argv) > 4 else 0

    rate_str = f"{speed_pct:+d}%" if speed_pct != 0 else "+0%"
    pitch_str = f"{pitch_hz:+d}Hz" if pitch_hz != 0 else "+0Hz"

    out_file.parent.mkdir(parents=True, exist_ok=True)

    import edge_tts
    communicate = edge_tts.Communicate(text, DEFAULT_VOICE, rate=rate_str, pitch=pitch_str)
    await communicate.save(str(out_file))
    print(f"SUCCESS:{out_file}")

if __name__ == "__main__":
    asyncio.run(main())
