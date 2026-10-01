import subprocess
from pathlib import Path

import pytest

from transcribe.media import split


TONE_SEC = 50
SILENCE_SEC = 3
FRAGMENTS = 6


def _pause_intervals():
    intervals = []
    offset = 0.0
    for _ in range(FRAGMENTS - 1):
        offset += TONE_SEC
        intervals.append((offset, offset + SILENCE_SEC))
        offset += SILENCE_SEC
    return intervals


PAUSES = _pause_intervals()


def _ffmpeg(args, tmp_path):
    res = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, res.stderr
    return res


def _duration(path):
    res = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, res.stderr
    return float(res.stdout.strip())


@pytest.fixture
def tone_with_pauses(tmp_path):
    for i in range(FRAGMENTS):
        _ffmpeg(
            [
                "-f",
                "lavfi",
                "-i",
                f"sine=frequency=440:sample_rate=16000:duration={TONE_SEC}",
                "-ac",
                "1",
                "-c:a",
                "flac",
                f"tone{i}.flac",
            ],
            tmp_path,
        )
        if i < FRAGMENTS - 1:
            _ffmpeg(
                [
                    "-f",
                    "lavfi",
                    "-i",
                    f"anullsrc=r=16000:cl=mono",
                    "-t",
                    str(SILENCE_SEC),
                    "-ac",
                    "1",
                    "-c:a",
                    "flac",
                    f"silence{i}.flac",
                ],
                tmp_path,
            )

    lines = []
    for i in range(FRAGMENTS):
        lines.append(f"file 'tone{i}.flac'")
        if i < FRAGMENTS - 1:
            lines.append(f"file 'silence{i}.flac'")
    (tmp_path / "list.txt").write_text("\n".join(lines) + "\n")

    out = tmp_path / "tone_with_pauses.flac"
    _ffmpeg(
        ["-f", "concat", "-safe", "0", "-i", "list.txt", "-c:a", "flac", str(out)],
        tmp_path,
    )
    return out


def test_split_by_pauses(tone_with_pauses, tmp_path):
    parts = split(
        tone_with_pauses,
        tmp_path,
        target_sec=100,
        window_sec=30,
        max_bytes=1,
    )

    assert len(parts) >= 3
    assert all(p.cut == "pause" for p in parts)

    for p in parts[1:]:
        inside = any(
            start - 1 <= p.offset_sec <= end + 1 for start, end in PAUSES
        )
        assert inside, f"boundary {p.offset_sec} not inside a pause"

    total = sum(p.duration_sec for p in parts)
    duration = _duration(tone_with_pauses)
    assert abs(total - duration) <= 1.0

    for prev, cur in zip(parts, parts[1:]):
        assert cur.offset_sec > prev.offset_sec
        assert cur.offset_sec >= prev.offset_sec + prev.duration_sec - 1e-6


def test_split_hard_cut_without_pauses(tmp_path):
    tone = tmp_path / "tone240.flac"
    _ffmpeg(
        [
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:sample_rate=16000:duration=240",
            "-ac",
            "1",
            "-c:a",
            "flac",
            str(tone),
        ],
        tmp_path,
    )

    parts = split(tone, tmp_path, target_sec=100, window_sec=10, max_bytes=1)
    assert any(p.cut == "hard" for p in parts)


def test_small_file_single_part(tmp_path):
    tone = tmp_path / "small.flac"
    _ffmpeg(
        [
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:sample_rate=16000:duration=5",
            "-ac",
            "1",
            "-c:a",
            "flac",
            str(tone),
        ],
        tmp_path,
    )

    parts = split(
        tone,
        tmp_path,
        target_sec=1200,
        window_sec=60,
        max_bytes=tone.stat().st_size + 1024,
    )
    assert len(parts) == 1
    assert parts[0].offset_sec == 0
