import sys
import types

import pytest

from transcribe import media
from transcribe.keys import ArgError


def _install_getaddrinfo(monkeypatch):
    """Резолв хост в самого себя (числовые адреса остаются числами)."""

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


def test_check_host_rejects_private_loopback(monkeypatch):
    _install_getaddrinfo(monkeypatch)
    with pytest.raises(ArgError):
        media.check_host("http://127.0.0.1/a.mp3")


def test_check_host_rejects_private_rfc1918(monkeypatch):
    _install_getaddrinfo(monkeypatch)
    with pytest.raises(ArgError):
        media.check_host("http://10.0.0.1/a.mp3")


def test_check_host_rejects_other_scheme(monkeypatch):
    with pytest.raises(ArgError):
        media.check_host("ftp://x/a.mp3")


def test_check_host_accepts_public(monkeypatch):
    _install_getaddrinfo(monkeypatch)
    media.check_host("https://example.com/a.mp3")


def test_cli_private_loopback_not_downloaded(monkeypatch):
    """http://127.0.0.1/a.mp3 → ArgError, requests/yt_dlp не вызваны."""
    _install_getaddrinfo(monkeypatch)
    called = []
    monkeypatch.setattr(media.requests, "get", lambda *a, **k: called.append(1))
    with pytest.raises(ArgError):
        media.check_host("http://127.0.0.1/a.mp3")
    assert called == []


class FakeResp:
    def __init__(self, status=200, headers=None, chunks=()):
        self.status_code = status
        self.headers = headers or {}
        self._chunks = chunks

    def iter_content(self, chunk_size=1):
        yield from self._chunks

    def close(self):
        pass


def test_fetch_direct_downloads_not_page(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    monkeypatch.setattr(
        media.requests, "get", lambda *a, **k: FakeResp(chunks=[b"a", b"b"])
    )
    path = media.fetch_direct("https://example.com/a.mp3", tmp_path)
    assert path.read_bytes() == b"ab"
    assert path.name == "fetch.mp3"


def test_fetch_direct_filename_without_ext(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    monkeypatch.setattr(
        media.requests, "get", lambda *a, **k: FakeResp(chunks=[b"a"])
    )
    path = media.fetch_direct("https://example.com/download?id=1", tmp_path)
    assert path.name == "fetch.bin"


def test_fetch_direct_redirect_to_private_rejected(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    responses = iter(
        [
            FakeResp(302, {"Location": "http://192.168.1.1/b.mp3"}),
            FakeResp(chunks=[b"x"]),
        ]
    )
    monkeypatch.setattr(media.requests, "get", lambda *a, **k: next(responses))
    with pytest.raises(ArgError):
        media.fetch_direct("https://example.com/a.mp3", tmp_path)


def test_fetch_direct_over_limit_aborted(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    monkeypatch.setattr(
        media.requests,
        "get",
        lambda *a, **k: FakeResp(chunks=[b"1" * 1024, b"2" * 1024]),
    )
    with pytest.raises(ArgError):
        media.fetch_direct("https://example.com/a.mp3", tmp_path, max_bytes=1500)


def test_fetch_direct_http_error(monkeypatch, tmp_path):
    _install_getaddrinfo(monkeypatch)
    monkeypatch.setattr(media.requests, "get", lambda *a, **k: FakeResp(status=404))
    with pytest.raises(ArgError):
        media.fetch_direct("https://example.com/a.mp3", tmp_path)


def test_yt_dlp_lazy_import(monkeypatch):
    monkeypatch.delitem(sys.modules, "yt_dlp", raising=False)
    import transcribe.media

    assert "yt_dlp" not in sys.modules
    assert not hasattr(transcribe.media, "yt_dlp")


def test_fetch_page_ytdl_options(monkeypatch, tmp_path, fake_yt_dlp):
    _install_getaddrinfo(monkeypatch)
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
            return f"{tmp_path}/page.mp3"

    fake_yt_dlp.YoutubeDL = FakeYDL
    path, pid = media.fetch_page("https://www.youtube.com/watch?v=abc", tmp_path)
    assert pid == "abc"
    assert str(path) == f"{tmp_path}/page.mp3"
    opts = captured["opts"]
    assert opts["format"] == "bestaudio/best"
    assert opts["noplaylist"] is True
    assert opts["max_filesize"] == 2 * 1024**3
    assert opts["noprogress"] is True
    assert opts["js_runtimes"] == {"node": {}}


def test_fetch_page_download_error(monkeypatch, tmp_path, fake_yt_dlp):
    _install_getaddrinfo(monkeypatch)

    class FakeYDL:
        def __init__(self, opts):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def extract_info(self, url, download=True):
            raise fake_yt_dlp.utils.DownloadError("что-то сломалось")

        def prepare_filename(self, info):
            return f"{tmp_path}/page.mp3"

    fake_yt_dlp.YoutubeDL = FakeYDL
    with pytest.raises(ArgError) as exc:
        media.fetch_page("https://www.youtube.com/watch?v=abc", tmp_path)
    assert "обновить загрузчик" in str(exc.value)


def test_stems():
    assert media.url_stem("https://example.com/a.mp3") == "a"
    assert media.clean_stem("abc def!") == "abcdef"
    assert media.clean_stem("!!!") == "transcript"
