"""Журнал запусков расшифровки."""

import json
import os
import time

DEFAULT_STATE = "/root/workspaces/tools/state/transcribe"


def write(engine, model, fallback, rc, duration_s):
    """Дописать строку журнала. Ошибки журнала не валят команду."""
    try:
        state = os.environ.get("TRANSCRIBE_STATE", DEFAULT_STATE)
        os.makedirs(state, exist_ok=True)
        record = {
            "ts": int(time.time()),
            "engine": engine,
            "model": model,
            "fallback": fallback,
            "rc": rc,
            "duration_s": duration_s,
        }
        path = os.path.join(state, "runs.jsonl")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, (json.dumps(record) + "\n").encode())
        finally:
            os.close(fd)
    except Exception:
        pass
