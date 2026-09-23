import pytest

from transcribe import cli, engines, media, pipeline
from transcribe.cli import main
from transcribe.engines import EngineError
from transcribe.keys import load_key


def _tmp_src(tmp_path, content=b"audio"):
    p = tmp_path / "src.ogg"
    p.write_bytes(content)
    return str(p)


def _result(**kw):
    base = {
        "text": "hello",
        "segments": [],
        "engines": [],
        "fallback": False,
        "reasons": "",
        "warnings": [],
    }
    base.update(kw)
    return base


def _install_media(monkeypatch, tmp_path):
    flac = tmp_path / "audio.flac"
    flac.write_bytes(b"flac")
    monkeypatch.setattr(media, "probe", lambda path: 1.0)
    monkeypatch.setattr(media, "to_flac", lambda src, tmp: flac)
    parts = [media.Part(0, flac, 0.0, 1.0, "pause")]
    split_calls = []

    def _split(flac, tmp):
        split_calls.append(True)
        return parts

    monkeypatch.setattr(media, "split", _split)
    return flac, split_calls


def test_auto_assemblyai_whole_file(monkeypatch, tmp_path, capsys):
    src = _tmp_src(tmp_path)
    flac, split_calls = _install_media(monkeypatch, tmp_path)
    calls = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None):
        calls.append((list(paths), lang, engine, speakers, offsets))
        return _result(
            engines=[{"engine": "assemblyai", "model": "best", "parts": 1}]
        )

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src])  # engine default auto
    assert rc == 0
    assert split_calls == []
    assert calls == [([flac], None, "assemblyai", False, None)]
    assert "engine=assemblyai" in capsys.readouterr().err


def test_auto_assemblyai_fails_groq_parts(monkeypatch, tmp_path, capsys):
    src = _tmp_src(tmp_path)
    flac, split_calls = _install_media(monkeypatch, tmp_path)

    def fake_run(paths, lang, engine, speakers=False, offsets=None):
        if engine == "assemblyai":
            raise EngineError("assemblyai", 401, None, "bad key")
        return _result(
            engines=[{"engine": "groq", "model": "m", "parts": 1}]
        )

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src])
    assert rc == 0
    assert split_calls == [True]
    err = capsys.readouterr().err
    assert "fallback:" in err
    assert "assemblyai" in err


def test_engine_assemblyai_fails_no_groq(monkeypatch, tmp_path):
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    calls = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None):
        calls.append(engine)
        if engine == "assemblyai":
            raise EngineError("assemblyai", 401, None, "bad key")
        return _result()

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src, "--engine", "assemblyai"])
    assert rc == 3
    assert calls == ["assemblyai"]


def test_speakers_assemblyai_fails_no_groq(monkeypatch, tmp_path):
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    calls = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None):
        calls.append((engine, speakers))
        if engine == "assemblyai":
            raise EngineError("assemblyai", 401, None, "bad key")
        return _result()

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src, "--speakers"])
    assert rc == 3
    assert calls == [("assemblyai", True)]


def test_engine_groq_uses_split_no_assemblyai(monkeypatch, tmp_path):
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    calls = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None):
        calls.append((engine, speakers))
        return _result(
            engines=[{"engine": "groq", "model": "m", "parts": 1}]
        )

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src, "--engine", "groq"])
    assert rc == 0
    assert calls == [("groq", False)]


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
    rec = tmp_path / "rec.ogg"
    rec.write_bytes(b"x")
    secret = "SUPERSECRETR15"
    monkeypatch.setenv("FAKE_KEY", secret)
    load_key("FAKE_KEY", "unused.env", "fake")

    def boom(path):
        raise RuntimeError(f"взрыв {secret}")

    monkeypatch.setattr(media, "probe", boom)
    rc = main([str(rec)])
    assert rc == 3
    err = capsys.readouterr().err
    assert "***" in err
    assert secret not in err
    assert "Traceback" not in err
