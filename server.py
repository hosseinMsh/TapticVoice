#!/usr/bin/env python3
"""
nospeaker Persian Web Control Panel & Neural TTS Bridge
Optimized single-voice neural Persian model.
"""

import os
import sys
import json
import asyncio
import subprocess
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "web"
TEMP_AUDIO_DIR = BASE_DIR / "build" / "audio"
TEMP_AUDIO_DIR.mkdir(parents=True, exist_ok=True)

# Default optimized Neural Voice for Persian
DEFAULT_VOICE = "fa-IR-FaridNeural"

async def _synthesize_edge_tts(text: str, output_mp3: Path, rate: str = "+0%", pitch: str = "+0Hz"):
    import edge_tts
    communicate = edge_tts.Communicate(text, DEFAULT_VOICE, rate=rate, pitch=pitch)
    await communicate.save(str(output_mp3))

AUDIO_FILTER_HAPTIC = (
    "highpass=f=120,lowpass=f=3800,"
    "equalizer=f=1000:t=q:w=1.2:g=3.5,"
    "equalizer=f=2200:t=q:w=1.2:g=4.0,"
    "compand=attacks=0.02:decays=0.1:points=-60/-60|-20/-6|0/-1:gain=2"
)

def generate_audio(text: str, speed_pct: int = 0, pitch_hz: int = 0, volume: int = 100) -> Path:
    """Generate high-quality Persian speech using Neural TTS, converted to 16kHz float32 WAV with haptic mastering."""
    target_wav = TEMP_AUDIO_DIR / "speech_16k.wav"
    raw_mp3 = TEMP_AUDIO_DIR / "speech_neural.mp3"
    
    # Format rate and pitch strings for edge_tts
    rate_str = f"{speed_pct:+d}%" if speed_pct != 0 else "+0%"
    pitch_str = f"{pitch_hz:+d}Hz" if pitch_hz != 0 else "+0Hz"

    used_neural = False
    try:
        asyncio.run(_synthesize_edge_tts(text, raw_mp3, rate=rate_str, pitch=pitch_str))
        if raw_mp3.exists() and raw_mp3.stat().st_size > 0:
            used_neural = True
    except Exception as e:
        print(f"Edge TTS warning: {e}, falling back to local engine...")
        used_neural = False

    if used_neural:
        # Convert MP3 to 16kHz float32 mono WAV for nospeaker with haptic EQ
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
    else:
        # Local fallback using espeak-ng if offline
        raw_wav = TEMP_AUDIO_DIR / "speech_raw.wav"
        cmd_espeak = [
            "/opt/homebrew/bin/espeak-ng",
            "-v", "fa",
            "-s", "150",
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

    return target_wav

def play_on_trackpad(wav_path: Path, caption: str) -> subprocess.Popen:
    """Run nospeaker with --file to actuate the Force Touch trackpad motor."""
    nospeaker_bin = BASE_DIR / "nospeaker"
    if not nospeaker_bin.exists():
        raise FileNotFoundError("nospeaker binary not found. Please compile it first.")
    
    cmd = [str(nospeaker_bin), "--file", str(wav_path), caption]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return proc

class RequestHandler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/status":
            bin_exists = (BASE_DIR / "nospeaker").exists()
            self.send_json({
                "ready": bin_exists,
                "model": "Persian Neural Core (بهینه‌شده برای فارسی)",
                "voice": DEFAULT_VOICE,
                "platform": sys.platform
            })
        elif path == "/api/preview.wav":
            target_wav = TEMP_AUDIO_DIR / "speech_16k.wav"
            if target_wav.exists():
                data = target_wav.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.end_headers()
        elif path == "/" or path == "/index.html":
            index_file = STATIC_DIR / "index.html"
            if index_file.exists():
                data = index_file.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b"{}"
        data = json.loads(body.decode("utf-8")) if body else {}

        if path == "/api/synthesize":
            text = data.get("text", "").strip()
            if not text:
                self.send_json({"error": "متن نمی‌تواند خالی باشد."}, 400)
                return
            speed_pct = int(data.get("speed_pct", 0))
            pitch_hz = int(data.get("pitch_hz", 0))
            volume = int(data.get("volume", 100))

            try:
                wav_path = generate_audio(text, speed_pct, pitch_hz, volume)
                self.send_json({
                    "success": True, 
                    "audio_url": f"/api/preview.wav?t={os.path.getmtime(wav_path)}"
                })
            except Exception as e:
                self.send_json({"error": str(e)}, 500)

        elif path == "/api/play":
            text = data.get("text", "").strip()
            speed_pct = int(data.get("speed_pct", 0))
            pitch_hz = int(data.get("pitch_hz", 0))
            volume = int(data.get("volume", 100))

            try:
                wav_path = generate_audio(text, speed_pct, pitch_hz, volume)
                proc = play_on_trackpad(wav_path, text)
                self.send_json({
                    "success": True, 
                    "message": "ارتعاش صوتی بهینه‌شده روی موتور ترک‌پد اعمال شد."
                })
            except Exception as e:
                self.send_json({"error": str(e)}, 500)
        else:
            self.send_response(404)
            self.end_headers()

def run_server(port=8080):
    server = HTTPServer(("127.0.0.1", port), RequestHandler)
    print(f"Neural Persian NoSpeaker Server started at http://127.0.0.1:{port}")
    server.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8089
    run_server(port)
