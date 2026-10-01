import pytest

from transcribe.keys import ArgError, KeyMissing, load_key, redact


def test_env_priority_over_file(tmp_path, monkeypatch):
    f = tmp_path / "keys.env"
    f.write_text("GROQ_API_KEY=from_file\n")
    monkeypatch.setenv("GROQ_API_KEY", "from_env")
    assert load_key("GROQ_API_KEY", str(f), "groq") == "from_env"


def test_read_file_quotes_and_comments(tmp_path, monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    f = tmp_path / "keys.env"
    f.write_text("# комментарий\nGROQ_API_KEY=\" mykey \"\nOTHER=x\n")
    assert load_key("GROQ_API_KEY", str(f), "groq") == "mykey"


def test_no_key_raises_KeyMissing_without_value(tmp_path, monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    monkeypatch.delenv("TRANSCRIBE_GROQ_ENV", raising=False)
    f = tmp_path / "keys.env"
    f.write_text("OTHER=x\n")
    with pytest.raises(KeyMissing) as exc:
        load_key("GROQ_API_KEY", str(f), "groq")
    msg = str(exc.value)
    assert "GROQ_API_KEY" in msg
    assert str(f) in msg
    assert "mykey" not in msg


def test_env_path_outside_secrets_and_temp_raises_ArgError(monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    outside = "/root/workspaces/tools/.worktrees/056-transcribe/nope.env"
    monkeypatch.setenv("TRANSCRIBE_GROQ_ENV", outside)
    with pytest.raises(ArgError):
        load_key("GROQ_API_KEY", "unused.env", "groq")


def test_redact_removes_key_value(tmp_path, monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "SUPERSECRETXYZ")
    load_key("GROQ_API_KEY", str(tmp_path / "unused.env"), "groq")
    out = redact("ошибка: SUPERSECRETXYZ не сработало")
    assert "SUPERSECRETXYZ" not in out
    assert "***" in out
