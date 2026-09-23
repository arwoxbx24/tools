"""A3 red: engine fallback / switching behaviour for transcribe.pipeline.run."""

import pytest

from transcribe import pipeline
from transcribe.cli import AllEnginesFailed
from transcribe.engines import ENGINES
from transcribe.engines.groq_engine import EngineError


GROQ_TEXT = "groq result"
ASSEMBLYAI_TEXT = "assemblyai result"


def _sleep_noop(_seconds: float) -> None:
    return None


def _find(records, name):
    for record in records:
        if record["engine"] == name:
            return record
    return None


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
    monkeypatch.setattr(pipeline.time, "sleep", _sleep_noop)


def test_groq_answers_text(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("ok", GROQ_TEXT)])
    assemblyai = FakeEngine("assemblyai")
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    result = pipeline.run(["part.flac"], "en")

    assert result["text"] == GROQ_TEXT
    assert groq.calls == 1
    assert assemblyai.calls == 0
    assert result["fallback"] is False
    assert _find(result["engines"], "groq")["parts"] == 1
    assert _find(result["engines"], "assemblyai") is None


def test_groq_401_falls_back_to_assemblyai(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("err", 401, 0)])
    assemblyai = FakeEngine("assemblyai", behaviors=[("ok", ASSEMBLYAI_TEXT)])
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    result = pipeline.run(["part.flac"], "en")

    assert result["text"] == ASSEMBLYAI_TEXT
    assert result["fallback"] is True
    assert "groq" in result["reasons"]


def test_groq_retries_429_with_short_retry_after(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("err", 429, 5), ("ok", GROQ_TEXT)])
    assemblyai = FakeEngine("assemblyai")
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    result = pipeline.run(["part.flac"], "en")

    assert groq.calls == 2
    assert assemblyai.calls == 0
    assert result["text"] == GROQ_TEXT
    assert result["fallback"] is False


def test_groq_429_long_retry_after_falls_back(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("err", 429, 600)])
    assemblyai = FakeEngine("assemblyai", behaviors=[("ok", ASSEMBLYAI_TEXT)])
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    result = pipeline.run(["part.flac"], "en")

    assert assemblyai.calls == 1
    assert result["text"] == ASSEMBLYAI_TEXT
    assert result["fallback"] is True
    assert "groq" in result["reasons"]


def test_three_parts_failure_midway_splits_engines(monkeypatch):
    groq = FakeEngine(
        "groq", behaviors=[("ok", "part1 "), ("err", 500, 0)]
    )
    assemblyai = FakeEngine(
        "assemblyai", behaviors=[("ok", "part2 "), ("ok", "part3 ")]
    )
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    result = pipeline.run(["p1.flac", "p2.flac", "p3.flac"], "en")

    assert groq.calls == 2
    assert assemblyai.calls == 2
    assert _find(result["engines"], "groq")["parts"] == 1
    assert _find(result["engines"], "assemblyai")["parts"] == 2
    assert "part1 " in result["text"]
    assert "part2 " in result["text"]
    assert "part3 " in result["text"]
    assert result["fallback"] is True
    assert "groq" in result["reasons"]


def test_both_engines_fail_raises_all_engines_failed(monkeypatch):
    groq = FakeEngine("groq", behaviors=[("err", 500, 0)])
    assemblyai = FakeEngine("assemblyai", behaviors=[("err", 500, 0)])
    _install(monkeypatch, groq=groq, assemblyai=assemblyai)

    with pytest.raises(AllEnginesFailed):
        pipeline.run(["part.flac"], "en")


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
