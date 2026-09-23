import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from transcribe.keys import ArgError

MAX_SECONDS = 36000


@dataclass
class Part:
    index: int
    path: Path
    offset_sec: float
    duration_sec: float
    cut: str


def _find_pauses(flac):
    res = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "info",
            "-i",
            str(flac),
            "-af",
            "silencedetect=noise=-30dB:d=0.5",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
    )
    pauses = []
    start = None
    for line in res.stderr.splitlines():
        m_start = re.search(r"silence_start:\s*([0-9.]+)", line)
        m_end = re.search(r"silence_end:\s*([0-9.]+)", line)
        if m_start:
            start = float(m_start.group(1))
        elif m_end is not None and start is not None:
            pauses.append((start, float(m_end.group(1))))
            start = None
    return pauses


def _cut(flac, start, end, out):
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-v",
            "error",
            "-ss",
            str(start),
            "-to",
            str(end),
            "-i",
            str(flac),
            "-c:a",
            "flac",
            str(out),
        ],
        check=True,
    )


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


def split(flac, tmpdir, target_sec=1200, window_sec=60, max_bytes=24 * 1024 * 1024):
    flac = Path(flac)
    tmpdir = Path(tmpdir)
    duration = probe(flac)
    if flac.stat().st_size <= max_bytes:
        return [Part(0, flac, 0.0, duration, "pause")]

    pauses = _find_pauses(flac)

    # Планируем границы частей: (boundary, cut).
    boundaries = [(0.0, "pause")]
    pos = 0.0
    # Хвост до target_sec + window_sec оставляем целым, иначе последняя
    # часть без подходящей паузы резалась бы "в жёсткую" и теряла бы паузу.
    while duration - pos > target_sec + window_sec:
        t = pos + target_sec
        best = None
        for start, end in pauses:
            mid = (start + end) / 2
            if t - window_sec <= mid <= t + window_sec:
                if best is None or abs(mid - t) < abs(best - t):
                    best = mid
        if best is None:
            best, cut = t, "hard"
        else:
            cut = "pause"
        pos = best
        boundaries.append((pos, cut))

    # Вырезаем части; последняя граница — конец файла.
    parts = []
    for i, (start, cut) in enumerate(boundaries):
        end = boundaries[i + 1][0] if i + 1 < len(boundaries) else duration
        out = tmpdir / f"part_{i}.flac"
        _cut(flac, start, end, out)
        parts.append(Part(i, out, start, end - start, cut))

    _split_oversized(parts, tmpdir, target_sec, window_sec, max_bytes)
    return parts


def _split_oversized(parts, tmpdir, target_sec, window_sec, max_bytes):
    if max_bytes <= 1024 * 1024:
        return
    extra = []
    for part in parts:
        if part.path.stat().st_size > max_bytes:
            sub = split(
                part.path,
                tmpdir,
                target_sec // 2,
                window_sec,
                max_bytes,
            )
            extra.extend(sub)
    if extra:
        parts[:] = extra
