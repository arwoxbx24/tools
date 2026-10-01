"""A4: настройки вывода txt/srt/json в transcribe.formats."""

import json

import pytest

from transcribe import formats


def _result(segments):
    return {
        "text": "привет\nмир",
        "segments": segments,
        "engines": [{"engine": "groq", "model": "m", "parts": 2}],
        "fallback": False,
        "reasons": "",
        "warnings": [],
    }


def test_srt_two_segments_with_offset():
    segments = [
        {"start": 0.5, "end": 2.0, "text": "привет"},
        {"start": 3.25, "end": 4.5, "text": "мир"},
    ]
    out = formats.render(_result(segments), "srt")
    lines = out.splitlines()

    assert lines == [
        "1",
        "00:00:00,500 --> 00:00:02,000",
        "привет",
        "",
        "2",
        "00:00:03,250 --> 00:00:04,500",
        "мир",
        "",
    ]

    starts = [s["start"] for s in segments]
    assert starts == sorted(starts)
    assert all(seg["start"] < seg["end"] for seg in segments)


def test_json_keys():
    segments = [{"start": 0, "end": 1, "text": "hi"}]
    out = formats.render(_result(segments), "json")
    data = json.loads(out)
    assert set(data) == {"text", "segments", "engines", "fallback", "warnings"}
    assert data["segments"] == segments


def test_vtt_from_segments():
    segments = [
        {"start": 1.0, "end": 2.5, "text": "привет"},
        {"start": 3.0, "end": 3.75, "text": "мир"},
    ]
    out = formats.render(_result(segments), "vtt")
    lines = out.splitlines()
    assert lines[0] == "WEBVTT"
    assert lines[1] == ""
    assert "00:00:01.000 --> 00:00:02.500" in out
    assert "00:00:03.000 --> 00:00:03.750" in out


@pytest.mark.parametrize("fmt", ["srt", "vtt"])
def test_render_subtitles_passthrough(fmt):
    r = _result([])
    r["subtitles"] = f"готовые субтитры для {fmt}"
    assert formats.render(r, fmt) == r["subtitles"]
