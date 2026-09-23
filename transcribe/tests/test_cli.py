import pytest

from transcribe import cli, engines
from transcribe.cli import main
from transcribe.keys import load_key


def _tmp_src(tmp_path, content=b"audio"):
    p = tmp_path / "src.ogg"
    p.write_bytes(content)
    return str(p)


@pytest.mark.parametrize("engine", ["openai", "yandex", "gemini", "openrouter"])
def test_banned_engine(capsys, engine):
    rc = main(["src.ogg", "--engine", engine])
    assert rc == 2
    assert "разрешены: groq, assemblyai" in capsys.readouterr().err


def test_unknown_engine(capsys):
    rc = main(["src.ogg", "--engine", "nosuch"])
    assert rc == 2
    err = capsys.readouterr().err
    assert "nosuch" in err
    assert "разрешены: groq, assemblyai" in err


def test_speakers_with_groq(tmp_path, capsys):
    src = _tmp_src(tmp_path)
    rc = main([src, "--engine", "groq", "--speakers"])
    assert rc == 2


def test_missing_file(capsys):
    rc = main(["/no/such/file.ogg"])
    assert rc == 2


def test_empty_file(tmp_path, capsys):
    src = _tmp_src(tmp_path, content=b"")
    rc = main([src])
    assert rc == 2


def test_help_prints_exit_codes(capsys):
    rc = main(["--help"])
    out = capsys.readouterr().out
    assert rc == 0
    for code in ("0", "2", "3", "4"):
        assert code in out


def test_fr009_fake_engine_one_line(tmp_path, monkeypatch, capsys):
    src = _tmp_src(tmp_path)
    fake = type(
        "Fake",
        (),
        {"name": "fake", "model": "m", "key_name": "K_API_KEY", "key_file": "f"},
    )
    monkeypatch.setattr(engines, "ENGINES", {**engines.ENGINES, "fake": fake})
    rc = main([src, "--engine", "fake"])
    assert rc == 3  # аргументы прошли, упёрлось в pipeline-stub


def test_unhandled_exception_redacted_no_traceback(tmp_path, monkeypatch, capsys):
    src = _tmp_src(tmp_path)
    secret = "SUPERSECRETR15"
    monkeypatch.setenv("FAKE_KEY", secret)
    load_key("FAKE_KEY", "unused.env", "fake")

    def boom(request):
        raise RuntimeError(f"взрыв {secret}")

    monkeypatch.setattr(cli, "pipeline_stub", boom)
    rc = main([src])
    assert rc == 3
    err = capsys.readouterr().err
    assert "***" in err
    assert "Traceback" not in err
