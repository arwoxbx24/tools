import json

import pytest

from transcribe import media, pipeline
from transcribe.cli import main


def _tmp_src(tmp_path, content=b"audio"):
    p = tmp_path / "src.ogg"
    p.write_bytes(content)
    return str(p)


def _install_media(monkeypatch, tmp_path):
    flac = tmp_path / "audio.flac"
    flac.write_bytes(b"flac")
    monkeypatch.setattr(media, "probe", lambda path: 12.0)
    monkeypatch.setattr(media, "to_flac", lambda src, tmp: flac)
    monkeypatch.setattr(
        media, "split", lambda flac, tmp: [media.Part(0, flac, 0.0, 12.0, "pause")]
    )
    return flac


def _result(**kw):
    base = {
        "text": "секретная расшифровка",
        "segments": [],
        "engines": [{"engine": "assemblyai", "model": "best", "parts": 1}],
        "fallback": False,
        "reasons": "",
        "warnings": [],
    }
    base.update(kw)
    return base


def _read_journal(tmp_path):
    lines = (tmp_path / "runs.jsonl").read_text().splitlines()
    return [json.loads(line) for line in lines]


def test_journal_success_row_no_transcript(monkeypatch, tmp_path):
    monkeypatch.setenv("TRANSCRIBE_STATE", str(tmp_path))
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    monkeypatch.setattr(pipeline, "run", lambda *a, **k: _result())
    rc = main([src])
    assert rc == 0
    rows = _read_journal(tmp_path)
    assert len(rows) == 1
    row = rows[0]
    assert set(row) == {"ts", "engine", "model", "fallback", "rc", "duration_s"}
    assert row == {
        "ts": row["ts"],
        "engine": "assemblyai",
        "model": "best",
        "fallback": None,
        "rc": 0,
        "duration_s": 12.0,
    }
    raw = (tmp_path / "runs.jsonl").read_text()
    assert "секретная расшифровка" not in raw


def test_journal_rc2_row_for_banned_engine(monkeypatch, tmp_path):
    monkeypatch.setenv("TRANSCRIBE_STATE", str(tmp_path))
    rc = main(["src.ogg", "--engine", "bitrix"])
    assert rc == 2
    rows = _read_journal(tmp_path)
    assert len(rows) == 1
    assert set(rows[0]) == {"ts", "engine", "model", "fallback", "rc", "duration_s"}
    assert rows[0]["rc"] == 2


def test_journal_unwritable_state_still_rc0(monkeypatch, tmp_path):
    blocker = tmp_path / "blocker"
    blocker.write_bytes(b"x")
    monkeypatch.setenv("TRANSCRIBE_STATE", str(blocker / "sub"))
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    monkeypatch.setattr(pipeline, "run", lambda *a, **k: _result())
    rc = main([src])
    assert rc == 0
    assert not (blocker / "sub" / "runs.jsonl").exists()
