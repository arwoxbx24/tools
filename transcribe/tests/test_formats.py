"""A4: настройки вывода txt/srt/json в transcribe.formats."""

import json

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
