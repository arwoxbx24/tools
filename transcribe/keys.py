import os
import tempfile
from pathlib import Path


class ArgError(Exception):
    """Ошибка аргументов или конфигурации."""


class KeyMissing(Exception):
    """Запрошенный ключ не найден ни в окружении, ни в env-файле."""


_SECRETS: set[str] = set()
_SECRETS_HOME = Path("/root/workspaces/secrets")


def _register_secret(value: str) -> None:
    _SECRETS.add(value)


def _validate_env_path(path: Path) -> None:
    resolved = path.resolve()
    allowed = (
        Path(_SECRETS_HOME).resolve(),
        Path(tempfile.gettempdir()).resolve(),
    )
    if not any(resolved.is_relative_to(root) for root in allowed):
        raise ArgError(f"env-файл вне разрешённых каталогов: {path}")


def _read_key_file(name: str, path: Path) -> str:
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            continue
        if key.strip() != name:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1].strip()
        return value
    raise KeyMissing(f"Ключ {name} не задан (env {name} или файл {path})")


def load_key(name: str, path: str, engine: str) -> str:
    env_file = os.environ.get(f"TRANSCRIBE_{engine.upper()}_ENV", path)
    value = os.environ.get(name)
    if value is None:
        _validate_env_path(Path(env_file))
        value = _read_key_file(name, Path(env_file))
    _register_secret(value)
    return value


def redact(text: str) -> str:
    for secret in sorted(_SECRETS, key=len, reverse=True):
        if secret:
            text = text.replace(secret, "***")
    return text
