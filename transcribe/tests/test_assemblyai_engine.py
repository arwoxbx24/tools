"""A2: экспорт субтитров srt/vtt у AssemblyAI до удаления транскрипта."""

import sys
import types

from transcribe.engines import assemblyai_engine
from transcribe.engines.groq_engine import EngineError


class FakeUtterance:
    def __init__(self, start, end, text, speaker=None):
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker


class FakeTranscriptType:
    calls = []

    @classmethod
    def delete_by_id(cls, transcript_id):
        cls.calls.append("delete")


class FakeTranscript:
    def __init__(self, calls):
        self.id = "transcript-1"
        self.status = "completed"
        self.error = None
        self.text = "привет мир"
        self.utterances = [
            FakeUtterance(1000, 2500, "привет"),
            FakeUtterance(3000, 3750, "мир"),
        ]
        self.calls = calls

    def export_subtitles_vtt(self):
        self.calls.append("export_vtt")
        return "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nпривет"

    def export_subtitles_srt(self):
        self.calls.append("export_srt")
        return "1\n00:00:01,000 --> 00:00:02,500\nпривет"


def _fake_aai(monkeypatch, transcript):
    aai = types.SimpleNamespace(
        settings=types.SimpleNamespace(api_key=None),
        TranscriptionConfig=lambda **kw: kw,
        TranscriptStatus=types.SimpleNamespace(error="error"),
        Transcript=FakeTranscriptType,
    )

    class FakeTranscriber:
        result = transcript

        def __init__(self, config=None):
            self.config = config

        def transcribe(self, path):
            return self.result

    aai.Transcriber = FakeTranscriber
    monkeypatch.setitem(sys.modules, "assemblyai", aai)
    monkeypatch.setattr(
        assemblyai_engine, "load_key", lambda *a, **kw: "fake-key"
    )
    return aai


def test_vtt_export_before_delete(monkeypatch):
    calls = []
    FakeTranscriptType.calls = calls
    _fake_aai(monkeypatch, FakeTranscript(calls))

    result = assemblyai_engine.AssemblyAIEngine().transcribe(
        "x.flac", "ru", subtitles="vtt"
    )

    assert calls == ["export_vtt", "delete"]
    assert result["subtitles"].startswith("WEBVTT")


def test_srt_export_before_delete(monkeypatch):
    calls = []
    FakeTranscriptType.calls = calls
    _fake_aai(monkeypatch, FakeTranscript(calls))

    result = assemblyai_engine.AssemblyAIEngine().transcribe(
        "x.flac", "ru", subtitles="srt"
    )

    assert calls == ["export_srt", "delete"]
    assert result["subtitles"].startswith("1\n")


def test_no_export_when_subtitles_none(monkeypatch):
    calls = []
    FakeTranscriptType.calls = calls
    _fake_aai(monkeypatch, FakeTranscript(calls))

    result = assemblyai_engine.AssemblyAIEngine().transcribe(
        "x.flac", "ru"
    )

    assert calls == ["delete"]
    assert result["subtitles"] is None


def test_export_error_becomes_warning(monkeypatch):
    calls = []
    FakeTranscriptType.calls = calls
    transcript = FakeTranscript(calls)

    def boom():
        raise RuntimeError("export failed")

    transcript.export_subtitles_vtt = boom
    _fake_aai(monkeypatch, transcript)

    result = assemblyai_engine.AssemblyAIEngine().transcribe(
        "x.flac", "ru", subtitles="vtt"
    )

    assert calls == ["delete"]
    assert any("vtt" in w for w in result["warnings"])
