import argparse
import os
import shutil
import signal
import sys
import tempfile
from pathlib import Path

from transcribe import engines, formats, media, pipeline
from transcribe.engines import AllEnginesFailed, EngineError
from transcribe.keys import ArgError, redact


def _fmt_clock(sec):
    sec = int(sec)
    hours, rem = divmod(sec, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def _transcribe(src, lang, engine, speakers):
    """Расшифровать локальный файл через пайплайн движков."""
    tmp = tempfile.mkdtemp()
    try:
        media.probe(src)
        flac = media.to_flac(src, tmp)
        if engine == "groq":
            return _transcribe_groq(flac, lang, tmp)

        # assemblyai / auto: один вызов на весь файл, без нарезки.
        reason = None
        try:
            result = pipeline.run([flac], lang, "assemblyai", speakers)
        except Exception as exc:
            if engine == "assemblyai" or speakers:
                raise
            reason = f"assemblyai: {redact(str(exc))}"
        else:
            return result, 1

        # авто: сбой AssemblyAI → Groq по частям с пометкой fallback.
        result, num_parts = _transcribe_groq(flac, lang, tmp)
        result["fallback"] = True
        result["reasons"] = [reason]
        return result, num_parts
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _transcribe_groq(flac, lang, tmp):
    parts = media.split(flac, tmp)
    result = pipeline.run(
        [p.path for p in parts],
        lang,
        "groq",
        False,
        offsets=[p.offset_sec for p in parts],
    )
    for part in parts:
        if part.cut == "hard":
            result["warnings"].append(
                f"жёсткий рез на {_fmt_clock(part.offset_sec)}"
            )
    return result, len(parts)


def _save(args, text, fmt="txt"):
    """Сохранить расшифровку в файл, вернуть путь."""
    if args.out:
        if os.path.islink(args.out):
            raise ArgError("--out указывает на симлинк")
        path = Path(args.out)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.chmod(path, 0o600)
    else:
        suffix = f".{fmt}"
        path = Path(args.src).with_suffix(suffix)
        if not os.access(path.parent, os.W_OK):
            path = Path.cwd() / (Path(args.src).stem + suffix)
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
        default="auto",
        help="движок транскрибации (auto (assemblyai → groq), assemblyai, groq)",
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
    parser.add_argument(
        "--format",
        default="txt",
        choices=["txt", "srt", "json"],
        help="формат вывода (txt, srt, json)",
    )
    parser.add_argument(
        "--timestamps",
        action="store_true",
        help="выводить субтитры srt (= --format srt)",
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
        if args.engine not in ("auto", "groq", "assemblyai"):
            raise EngineError(
                engine=args.engine,
                status=None,
                retry_after=None,
                message=f"движок {args.engine} не реализован",
            )
        result, num_parts = _transcribe(
            args.src, args.lang, args.engine, args.speakers
        )
    except ArgError as exc:
        print(f"transcribe: error: {exc}", file=sys.stderr)
        return 2
    except EngineError as exc:
        print(f"transcribe: error: {exc.message}", file=sys.stderr)
        return 3
    except Exception as exc:
        print(redact(str(exc)), file=sys.stderr)
        return 3

    fmt = "srt" if args.timestamps else args.format
    text = formats.render(result, fmt)
    print(text)
    print(f"transcribe: parts={num_parts}", file=sys.stderr)
    records = "; ".join(
        f"engine={r['engine']} model={r['model']} parts={r['parts']}"
        for r in result["engines"]
    )
    print(f"transcribe: {records}", file=sys.stderr)
    if result["fallback"]:
        print(f"transcribe: fallback: {result['reasons']}", file=sys.stderr)
    for warning in result["warnings"]:
        print(f"transcribe: warning: {warning}", file=sys.stderr)

    if not args.no_save:
        try:
            path = _save(args, text, fmt)
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
