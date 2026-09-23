import argparse
import os
import sys

from transcribe import engines
from transcribe.keys import redact


class AllEnginesFailed(Exception):
    """Все движки транскрибации завершились неудачей."""


def pipeline_stub(*args, **kwargs):
    raise AllEnginesFailed()


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
    args = parser.parse_args(argv)

    if args.engine in engines.BANNED:
        print(
            f"движок {args.engine} запрещён; разрешены: {', '.join(engines.ORDER)}",
            file=sys.stderr,
        )
        return 2
    if args.engine not in engines.ENGINES:
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

    try:
        pipeline_stub(args.src)
    except AllEnginesFailed:
        return 3
    except Exception as exc:
        print(redact(str(exc)), file=sys.stderr)
        return 3
    return 0


def main(argv=None) -> int:
    try:
        return _run(argv)
    except SystemExit as exc:
        return exc.code if exc.code is not None else 0
