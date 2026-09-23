"""Транскрибация списка частей фиксированным движком."""

import time

from transcribe import engines
from transcribe.engines import AllEnginesFailed, EngineError


def _invoke(engine, path, lang, speakers, subtitles=None):
    """Вызвать движок: либо класс с .transcribe, либо готовый callable."""
    transcribe = getattr(engine, "transcribe", None)
    if transcribe is not None:
        if getattr(engine, "name", None) == "assemblyai":
            return engine().transcribe(path, lang, speakers, subtitles)
        return engine().transcribe(path, lang, speakers)
    return engine(path, lang, speakers)


def _result(texts, segments, warnings, parts, fallback, reasons, subtitles):
    payload = {
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
    subs = [s for s in subtitles if s]
    if len(subs) == 1:
        payload["subtitles"] = subs[0]
    return payload


def _shift(segments, offset):
    """Сместить таймкоды сегментов на offset_sec части."""
    if not offset:
        return segments
    shifted = []
    for seg in segments:
        s = dict(seg)
        s["start"] = seg["start"] + offset
        s["end"] = seg["end"] + offset
        shifted.append(s)
    return shifted


def _run_fixed(name, paths, lang, speakers, offsets, subtitles=None):
    """Транскрибировать все части строго одним движком."""
    engine_obj = engines.ENGINES[name]
    texts = []
    segments = []
    warnings = []
    subtitles_out = []
    parts = {"groq": 0, "assemblyai": 0}

    def invoke(path, offset):
        try:
            return _invoke(engine_obj, path, lang, speakers, subtitles)
        except EngineError as exc:
            if (
                name == "groq"
                and exc.status == 429
                and exc.retry_after is not None
                and exc.retry_after <= 60
            ):
                time.sleep(exc.retry_after)
                return _invoke(engine_obj, path, lang, speakers, subtitles)
            raise

    try:
        for path, offset in zip(paths, offsets):
            res = invoke(path, offset)
            texts.append(res["text"])
            segments.extend(_shift(res.get("segments", []), offset))
            warnings.extend(res.get("warnings", []))
            subtitles_out.append(res.get("subtitles"))
            parts[name] += 1
    except EngineError as exc:
        raise AllEnginesFailed(str(exc)) from exc
    return _result(texts, segments, warnings, parts, False, [], subtitles_out)


def run(flac_paths, lang, engine="groq", speakers=False, offsets=None, subtitles=None):
    if offsets is None:
        offsets = [0.0] * len(flac_paths)
    if speakers:
        return _run_fixed(
            "assemblyai", flac_paths[:1], lang, True, offsets[:1], subtitles
        )
    return _run_fixed(engine, flac_paths, lang, False, offsets, subtitles)
