"""A3 red: engine fallback / switching behaviour for transcribe.pipeline.run."""

import pytest

from transcribe import pipeline
from transcribe.cli import AllEnginesFailed
from transcribe.engines import ENGINES
from transcribe.engines.groq_engine import EngineError


GROQ_TEXT = "groq result"
ASSEMBLYAI_TEXT = "assemblyai result"


class FakeEngine:
    """Serves one behavior per call and records its own invocations."""

    def __init__(self, name, behaviors=(), model="fake-model"):
        self.name = name
        self.model = model
        self.behaviors = list(behaviors)
        self.calls = 0
        self.speakers_used = []

    def __call__(self, flac_paths, lang, speakers=False):
        self.calls += 1
        self.speakers_used.append(speakers)
        behavior = self.behaviors[self.calls - 1]
        if behavior[0] == "err":
            raise EngineError(self.name, behavior[1], behavior[2], "boom")
        return {"text": behavior[1], "segments": []}


def _install(monkeypatch, groq=None, assemblyai=None):
    monkeypatch.setitem(ENGINES, "groq", groq or FakeEngine("groq"))
    monkeypatch.setitem(
        ENGINES, "assemblyai", assemblyai or FakeEngine("assemblyai")
    )


def test_fixed_groq_engine_failure_no_fallback(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("err", 500, 0)])
    assemblyai = FakeEngine("assemblyai")
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    with pytest.raises(AllEnginesFailed):
        pipeline.run(["part.flac"], "en", engine="groq")
    assert assemblyai.calls == 0


def test_speakers_only_calls_assemblyai_with_speakers_true(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("ok", GROQ_TEXT)])
    assemblyai = FakeEngine("assemblyai", behaviors=[("ok", ASSEMBLYAI_TEXT)])
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    result = pipeline.run(["part.flac"], "en", speakers=True)

    assert groq.calls == 0
    assert assemblyai.calls == 1
    assert assemblyai.speakers_used == [True]
    assert result["text"] == ASSEMBLYAI_TEXT


def test_subtitles_passed_to_assemblyai_and_carried_out(monkeypatch):
    class AssemblyaiWithSubtitles:
        name = "assemblyai"
        model = "m"
        received = []

        def __init__(self):
            pass

        def transcribe(self, path, lang, speakers=False, subtitles=None):
            AssemblyaiWithSubtitles.received.append(
                (path, lang, speakers, subtitles)
            )
            return {
                "text": "x",
                "segments": [],
                "warnings": [],
                "subtitles": "WEBVTT\n\nготовые",
            }

    monkeypatch.setitem(
        ENGINES, "assemblyai", AssemblyaiWithSubtitles
    )

    result = pipeline.run(
        ["part.flac"], "en", engine="assemblyai", subtitles="vtt"
    )

    assert AssemblyaiWithSubtitles.received == [
        ("part.flac", "en", False, "vtt")
    ]
    assert result["subtitles"] == "WEBVTT\n\nготовые"
