import json
import os
import subprocess
from pathlib import Path

from transcribe.keys import ArgError

MAX_SECONDS = 36000


def probe(path) -> float:
    res = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type:format=duration",
            "-of",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        raise ArgError("файл не читается")
    data = json.loads(res.stdout)
    streams = data.get("streams", [])
    if not any(s.get("codec_type") == "audio" for s in streams):
        raise ArgError("нет звуковой дорожки")
    duration = float(data["format"]["duration"])
    if duration > MAX_SECONDS:
        raise ArgError("запись длиннее 10 ч")
    return duration


def to_flac(src, tmpdir) -> Path:
    out = Path(tmpdir) / "audio.flac"
    env = dict(os.environ)
    env.pop("GROQ_API_KEY", None)
    env.pop("ASSEMBLYAI_API_KEY", None)
    res = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-v",
            "error",
            "-i",
            str(src),
            "-vn",
            "-map",
            "0:a",
            "-ar",
            "16000",
            "-ac",
            "1",
            "-c:a",
            "flac",
            str(out),
        ],
        env=env,
    )
    if res.returncode != 0:
        raise ArgError("ffmpeg не смог извлечь звук")
    return out
