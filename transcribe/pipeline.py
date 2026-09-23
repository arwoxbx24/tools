"""Выбор движка транскрибации с переходом Groq → AssemblyAI при сбое."""

import time

from transcribe import engines
from transcribe.engines import AllEnginesFailed, EngineError

RETRY_STATUS = 429
RETRY_AFTER_LIMIT = 60


def _invoke(engine, path, lang, speakers):
    """Вызвать движок: либо класс с .transcribe, либо готовый callable."""
    transcribe = getattr(engine, "transcribe", None)
    if transcribe is not None:
        return engine().transcribe(path, lang, speakers)
    return engine(path, lang, speakers)


def _try_groq(path, lang):
    """Одна часть через Groq с одним повтором на короткий 429."""
    groq = engines.ENGINES["groq"]
    try:
        return _invoke(groq, path, lang, False)
    except EngineError as exc:
        if (
            exc.status == RETRY_STATUS
            and exc.retry_after is not None
            and exc.retry_after <= RETRY_AFTER_LIMIT
        ):
            time.sleep(exc.retry_after)
            return _invoke(groq, path, lang, False)
        raise


def _result(texts, segments, warnings, parts, fallback, reasons):
    return {
        "text": "\n".join(texts),
        "segments": segments,
        "engines": [
            {
                "engine": name,
                "model": getattr(engines.ENGINES[name], "model", None),
                "parts": parts[name],
            }
            for name in ("groq", "assemblyai")
            if parts[name] > 0
        ],
        "fallback": fallback,
        "reasons": "; ".join(reasons),
        "warnings": warnings,
    }


def _run_fixed(name, paths, lang, speakers):
    """Транскрибировать все части строго одним движком."""
    engine_obj = engines.ENGINES[name]
    texts = []
    segments = []
    warnings = []
    parts = {"groq": 0, "assemblyai": 0}
    try:
        for path in paths:
            res = _invoke(engine_obj, path, lang, speakers)
            texts.append(res["text"])
            segments.extend(res.get("segments", []))
            warnings.extend(res.get("warnings", []))
            parts[name] += 1
    except EngineError as exc:
        raise AllEnginesFailed(str(exc)) from exc
    return _result(texts, segments, warnings, parts, False, [])


def _run_auto(paths, lang):
    """Groq по частям, при сбое — переход на AssemblyAI до конца."""
    texts = []
    segments = []
    warnings = []
    parts = {"groq": 0, "assemblyai": 0}
    fallback = False
    reasons = []

    for path in paths:
        if not fallback:
            try:
                res = _try_groq(path, lang)
                parts["groq"] += 1
            except EngineError as exc:
                fallback = True
                reasons.append(f"groq: {exc.status} {exc.message}")
        if fallback:
            try:
                res = _invoke(engines.ENGINES["assemblyai"], path, lang, False)
                parts["assemblyai"] += 1
            except EngineError as exc:
                raise AllEnginesFailed("; ".join(reasons)) from exc
        texts.append(res["text"])
        segments.extend(res.get("segments", []))
        warnings.extend(res.get("warnings", []))

    return _result(texts, segments, warnings, parts, fallback, reasons)


def run(flac_paths, lang, engine="auto", speakers=False):
    if speakers:
        return _run_fixed("assemblyai", flac_paths[:1], lang, True)
    if engine in ("groq", "assemblyai"):
        return _run_fixed(engine, flac_paths, lang, False)
    return _run_auto(flac_paths, lang)
