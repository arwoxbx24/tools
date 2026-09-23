import argparse
import os
import shutil
import signal
import sys
import tempfile
from pathlib import Path

from transcribe import engines, formats, media
from transcribe.engines import EngineError
from transcribe.keys import ArgError, redact


def _transcribe(src, lang):
    """Расшифровать локальный файл через двига groq."""
    tmp = tempfile.mkdtemp()
    try:
        media.probe(src)
        flac = media.to_flac(src, tmp)
        if os.path.getsize(flac) > 24 * 1024 * 1024:
            raise ArgError("запись длиннее одной части — нарезка в следующей версии")
        return engines.ENGINES["groq"]().transcribe(flac, lang)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _save(args, text):
    """Сохранить расшифровку в файл, вернуть путь."""
    if args.out:
        if os.path.islink(args.out):
            raise ArgError("--out указывает на симлинк")
        path = Path(args.out)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.chmod(path, 0o600)
    else:
        path = Path(args.src).with_suffix(".txt")
        if not os.access(path.parent, os.W_OK):
            path = Path.cwd() / (Path(args.src).stem + ".txt")
        n = 1
        while os.path.exists(path):
            path = path.with_name(f"{path.stem}.{n}{path.suffix}")
            n += 1
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, text.encode())
    finally:
        os.close(fd)
    return path


def _run(argv):
    parser = argparse.ArgumentParser(
        prog="transcribe",
        description="Транскрибация аудио через облачные движки.",
        epilog=(
            "Коды выхода:\n"
            "  0 — успех\n"
            "  2 — ошибка аргументов/конфигурации\n"
            "  3 — ошибка движка\n"
            "  4 — ошибка ключей"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("src", help="путь к аудио-файлу")
    parser.add_argument(
        "--engine",
        default="groq",
        help="движок транскрибации (groq, assemblyai)",
    )
    parser.add_argument(
        "--speakers",
        action="store_true",
        help="разделять реплики по спикерам",
    )
    parser.add_argument(
        "--lang",
        default=None,
        help="язык аудио (например, ru)",
    )
    parser.add_argument(
        "--no-save",
        action="store_true",
        help="не сохранять расшифровку в файл",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="путь для сохранения расшифровки",
    )
    args = parser.parse_args(argv)

    if args.engine in engines.BANNED:
        print(
            f"движок {args.engine} запрещён; разрешены: {', '.join(engines.ORDER)}",
            file=sys.stderr,
        )
        return 2
    if args.engine not in engines.ENGINES and args.engine != "auto":
        print(
            f"неизвестный движок {args.engine}; разрешены: {', '.join(engines.ORDER)}",
            file=sys.stderr,
        )
        return 2
    if args.speakers and args.engine == "groq":
        print("--speakers не поддерживается для двига groq", file=sys.stderr)
        return 2
    if not os.path.isfile(args.src):
        print(f"файл не найден: {args.src}", file=sys.stderr)
        return 2
    if os.path.getsize(args.src) == 0:
        print(f"пустой файл: {args.src}", file=sys.stderr)
        return 2
    if args.src.startswith(("http://", "https://")):
        print("transcribe: error: ссылки — в следующей версии", file=sys.stderr)
        return 2

    try:
        if args.engine not in ("auto", "groq"):
            raise EngineError(
                engine=args.engine,
                status=None,
                retry_after=None,
                message=f"движок {args.engine} не реализован",
            )
        result = _transcribe(args.src, args.lang)
    except ArgError as exc:
        print(f"transcribe: error: {exc}", file=sys.stderr)
        return 2
    except EngineError as exc:
        print(f"transcribe: error: {exc.message}", file=sys.stderr)
        return 3
    except Exception as exc:
        print(redact(str(exc)), file=sys.stderr)
        return 3

    text = formats.render(result, "txt")
    print(text)
    print("transcribe: engine=groq model=whisper-large-v3 parts=1", file=sys.stderr)

    if not args.no_save:
        try:
            path = _save(args, text)
        except ArgError as exc:
            print(f"transcribe: error: {exc}", file=sys.stderr)
            return 2
        print(f"transcribe: saved: {path}", file=sys.stderr)
    return 0


def main(argv=None) -> int:
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(143))
    try:
        return _run(argv)
    except SystemExit as exc:
        return exc.code if exc.code is not None else 0
