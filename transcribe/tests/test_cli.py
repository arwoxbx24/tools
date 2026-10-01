import json
import sys
import types

import pytest

from transcribe import cli, engines, media, pipeline
from transcribe.cli import main
from transcribe.engines import EngineError
from transcribe.keys import load_key


@pytest.fixture(autouse=True)
def _journal_state(tmp_path, monkeypatch):
    monkeypatch.setenv("TRANSCRIBE_STATE", str(tmp_path))


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


def _install_getaddrinfo(monkeypatch):
    def fake(host, port, *a, **k):
        return [(2, 1, 6, "", (host, port))]

    monkeypatch.setattr(media.socket, "getaddrinfo", fake)


@pytest.fixture
def fake_yt_dlp(monkeypatch):
    """Фейковый yt_dlp модуль для ленивого импорта в fetch_page."""
    module = types.ModuleType("yt_dlp")
    module.utils = types.SimpleNamespace(
        DownloadError=type("DownloadError", (Exception,), {})
    )
    module.YoutubeDL = None
    monkeypatch.setitem(sys.modules, "yt_dlp", module)
    return module


def test_link_loopback_rejected_no_network(monkeypatch):
    _install_getaddrinfo(monkeypatch)
    calls = []
    monkeypatch.setattr(media, "fetch_direct", lambda *a, **k: calls.append("d") or 0)
    monkeypatch.setattr(media, "fetch_page", lambda *a, **k: calls.append("p") or (0, ""))
    rc = main(["http://127.0.0.1/a.mp3"])
    assert rc == 2
    assert calls == []


def test_link_other_scheme_rejected_no_network(monkeypatch):
    calls = []
    monkeypatch.setattr(media, "fetch_direct", lambda *a, **k: calls.append(1))
    rc = main(["ftp://x/a.mp3"])
    assert rc == 2
    assert calls == []


def test_link_direct_uses_fetch_direct_saves_stem(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    flac, _ = _install_media(monkeypatch, tmp_path)
    monkeypatch.setattr(media, "check_host", lambda url: None)
    calls = {"d": 0, "p": 0}
    monkeypatch.setattr(media, "fetch_direct", lambda u, tmp: calls.__setitem__("d", calls["d"] + 1) or flac)
    monkeypatch.setattr(media, "fetch_page", lambda u, tmp: calls.__setitem__("p", calls["p"] + 1) or (flac, "abc"))
    monkeypatch.setattr(
        pipeline, "run",
        lambda *a, **k: _result(engines=[{"engine": "assemblyai", "model": "m", "parts": 1}]),
    )
    monkeypatch.chdir(tmp_path)
    rc = main(["https://example.com/a.mp3"])
    assert rc == 0
    assert calls == {"d": 1, "p": 0}
    assert (tmp_path / "a.txt").exists()


def test_link_page_youtube_ytdl_opts(monkeypatch, tmp_path, fake_yt_dlp):
    _install_getaddrinfo(monkeypatch)
    flac, _ = _install_media(monkeypatch, tmp_path)
    monkeypatch.setattr(media, "check_host", lambda url: None)
    captured = {}

    class FakeYDL:
        def __init__(self, opts):
            captured["opts"] = opts

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def extract_info(self, url, download=True):
            return {"id": "abc"}

        def prepare_filename(self, info):
            return f"{tmp_path}/whatever.mp3"

    fake_yt_dlp.YoutubeDL = FakeYDL
    monkeypatch.setattr(
        pipeline, "run",
        lambda *a, **k: _result(engines=[{"engine": "assemblyai", "model": "m", "parts": 1}]),
    )
    monkeypatch.chdir(tmp_path)
    rc = main(["https://www.youtube.com/watch?v=abc"])
    assert rc == 0
    opts = captured["opts"]
    assert opts["format"] == "bestaudio/best"
    assert opts["noplaylist"] is True
    assert opts["max_filesize"] == 2 * 1024**3
    assert opts["js_runtimes"] == {"node": {}}
    assert (tmp_path / "abc.txt").exists()


def test_link_fetch_error_returns_2(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    _install_media(monkeypatch, tmp_path)
    from transcribe.keys import ArgError

    monkeypatch.setattr(
        media, "fetch_direct", lambda u, tmp: (_ for _ in ()).throw(ArgError("файл больше лимита"))
    )
    rc = main(["https://example.com/a.mp3"])
    assert rc == 2


def test_auto_assemblyai_whole_file(monkeypatch, tmp_path, capsys):
    src = _tmp_src(tmp_path)
    flac, split_calls = _install_media(monkeypatch, tmp_path)
    calls = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
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

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
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


def test_auto_fallback_reason_is_string(monkeypatch, tmp_path, capsys):
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
        if engine == "assemblyai":
            raise EngineError("assemblyai", 401, None, "bad key")
        return _result(engines=[{"engine": "groq", "model": "m", "parts": 1}])

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src])
    assert rc == 0

    err = capsys.readouterr().err
    assert "transcribe: fallback: assemblyai:" in err
    assert "['" not in err

    row = json.loads((tmp_path / "runs.jsonl").read_text().splitlines()[0])
    assert isinstance(row["fallback"], str)
    assert row["fallback"].startswith("assemblyai: bad key")


def test_engine_assemblyai_fails_no_groq(monkeypatch, tmp_path):
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    calls = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
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

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
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

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
        calls.append((engine, speakers))
        return _result(
            engines=[{"engine": "groq", "model": "m", "parts": 1}]
        )

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src, "--engine", "groq"])
    assert rc == 0
    assert calls == [("groq", False)]


def test_format_vtt_saves_vtt_file(monkeypatch, tmp_path, capsys):
    src = _tmp_src(tmp_path)
    _install_media(monkeypatch, tmp_path)
    received = []

    def fake_run(paths, lang, engine, speakers=False, offsets=None, subtitles=None):
        received.append((engine, speakers, subtitles))
        return _result()

    monkeypatch.setattr(pipeline, "run", fake_run)
    rc = main([src, "--format", "vtt"])

    assert rc == 0
    assert received == [("assemblyai", False, "vtt")]
    assert (tmp_path / "src.vtt").exists()


@pytest.mark.parametrize("engine", ["openai", "yandex", "gemini", "openrouter"])
def test_banned_engine(capsys, engine):
    rc = main(["src.ogg", "--engine", engine])
    assert rc == 2
    assert "разрешены: assemblyai, groq" in capsys.readouterr().err


@pytest.mark.parametrize("engine", ["speechkit", "whisper-1", "google", "bitrix", "local"])
def test_new_banned_engines(capsys, engine):
    rc = main(["src.ogg", "--engine", engine])
    assert rc == 2
    assert "разрешены: assemblyai, groq" in capsys.readouterr().err


def test_unknown_engine(capsys):
    rc = main(["src.ogg", "--engine", "nosuch"])
    assert rc == 2
    err = capsys.readouterr().err
    assert "nosuch" in err
    assert "разрешены: assemblyai, groq" in err


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
