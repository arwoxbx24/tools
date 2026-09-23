import os
import stat

import pytest

from transcribe import cli, engines, media
from transcribe.cli import main


class Fake:
    def transcribe(self, path, lang, speakers=False):
        return {"text": "привет", "segments": []}


@pytest.fixture(autouse=True)
def setup(monkeypatch, tmp_path):
    monkeypatch.setitem(engines.ENGINES, "groq", Fake)
    monkeypatch.setattr(media, "probe", lambda p: 3.0)
    monkeypatch.setattr(media, "to_flac", lambda src, tmp: src)
    rec = tmp_path / "call.ogg"
    rec.write_bytes(b"x")
    return rec


def test_main_saves_output(setup, tmp_path, capsys):
    rec = setup
    assert main([str(rec)]) == 0
    out = capsys.readouterr().out
    assert out.strip() == "привет"
    f = tmp_path / "call.txt"
    assert f.exists()
    assert stat.S_IMODE(os.stat(f).st_mode) == 0o600


def test_second_call_creates_numbered_file(setup, tmp_path):
    rec = setup
    assert main([str(rec)]) == 0
    assert main([str(rec)]) == 0
    assert (tmp_path / "call.txt").exists()
    assert (tmp_path / "call.1.txt").exists()


def test_no_save(setup, tmp_path):
    rec = setup
    assert main([str(rec), "--no-save"]) == 0
    assert not (tmp_path / "call.txt").exists()


def test_out_option(setup, tmp_path):
    rec = setup
    out = tmp_path / "o.txt"
    out.write_text("old")
    assert main([str(rec), "--out", str(out)]) == 0
    assert out.read_text().strip() == "привет"


def test_out_symlink_is_rejected(setup, tmp_path, capsys):
    rec = setup
    link = tmp_path / "l.txt"
    link.symlink_to(tmp_path / "t.txt")
    assert main([str(rec), "--out", str(link)]) == 2


def test_stderr_logs_and_stdout_clean(setup, tmp_path, capsys):
    rec = setup
    assert main([str(rec)]) == 0
    captured = capsys.readouterr()
    assert "transcribe: saved:" in captured.err
    assert "engine=groq" in captured.err
    assert "transcribe:" not in captured.out
