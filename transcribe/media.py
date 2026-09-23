import json
import ipaddress
import os
import re
import socket
import subprocess
import urllib.parse
from dataclasses import dataclass
from pathlib import Path

import requests
import yt_dlp

from transcribe.keys import ArgError, redact

MAX_SECONDS = 36000

_DIRECT_EXTS = {
    "mp3", "wav", "ogg", "oga", "opus", "m4a", "flac", "aac", "amr",
    "webm", "mp4", "mkv", "mov", "avi", "3gp",
}


def url_ext(url):
    """Расширение пути URL без точки и в нижнем регистре ("" — если нет)."""
    return os.path.splitext(urllib.parse.urlparse(url).path)[1].lower().lstrip(".")


def is_direct(url):
    return url_ext(url) in _DIRECT_EXTS


def clean_stem(value):
    return re.sub(r"[^A-Za-z0-9._-]", "", value) or "transcript"


def url_stem(url):
    base = os.path.basename(urllib.parse.urlparse(url).path)
    return clean_stem(os.path.splitext(base)[0])


def check_host(url):
    """Проверить схему и публичность адреса. Ошибка — ArgError."""
    parts = urllib.parse.urlparse(url)
    scheme = parts.scheme.lower()
    if scheme not in ("http", "https"):
        raise ArgError(f"недопустимая схема ссылки: {scheme}")
    host = parts.hostname
    if not host:
        raise ArgError("в ссылке нет хоста")
    port = parts.port or (80 if scheme == "http" else 443)
    try:
        infos = socket.getaddrinfo(host, port)
    except OSError:
        raise ArgError("не удалось резолвить хост ссылки")
    for info in infos:
        addr = info[4][0]
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if (
            ip.is_private or ip.is_loopback or ip.is_link_local
            or ip.is_unspecified or ip.is_reserved or ip.is_multicast
        ):
            raise ArgError("ссылка ведёт на непубличный адрес")


def fetch_direct(url, tmpdir, max_bytes=2 * 1024**3):
    """Скачать прямой файл по ссылке с проверкой редиректов и лимита размера."""
    check_host(url)
    current = url
    for _ in range(6):
        check_host(current)
        resp = requests.get(
            current, stream=True, allow_redirects=False, timeout=300
        )
        try:
            if resp.status_code in (301, 302, 303, 307, 308):
                location = resp.headers.get("Location")
                if not location:
                    raise ArgError("редирект без Location")
                current = urllib.parse.urljoin(current, location)
                continue
            if 400 <= resp.status_code < 600:
                raise ArgError(f"HTTP {resp.status_code}")
            out = Path(tmpdir) / f"fetch{url_ext(current)}"
            total = 0
            with out.open("wb") as f:
                for chunk in resp.iter_content(chunk_size=64 * 1024):
                    if not chunk:
                        continue
                    total += len(chunk)
                    if total > max_bytes:
                        raise ArgError("файл больше лимита размера")
                    f.write(chunk)
            return out
        finally:
            resp.close()
    raise ArgError("слишком много редиректов")


def fetch_page(url, tmpdir):
    """Скачать страницу-видео через yt-dlp. Возвращает (путь, id)."""
    check_host(url)
    opts = {
        "format": "bestaudio/best",
        "noplaylist": True,
        "max_filesize": 2 * 1024**3,
        "outtmpl": f"{tmpdir}/page.%(ext)s",
        "quiet": True,
        "no_warnings": True,
        "js_runtimes": {"node": {}},
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=True)
            path = Path(ydl.prepare_filename(info))
    except yt_dlp.utils.DownloadError as exc:
        raise ArgError(
            f"загрузчик: {redact(str(exc))}; обновить загрузчик yt-dlp"
        )
    return path, info["id"]


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
