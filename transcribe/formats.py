import json


def _fmt_time(sec):
    ms = round(sec * 1000)
    hours, ms = divmod(ms, 3600000)
    minutes, ms = divmod(ms, 60000)
    seconds, ms = divmod(ms, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{ms:03d}"


def _render_srt(result):
    lines = []
    speaker_nums = {}
    for i, seg in enumerate(result["segments"], start=1):
        text = seg["text"]
        speaker = seg.get("speaker")
        if speaker:
            if speaker not in speaker_nums:
                speaker_nums[speaker] = len(speaker_nums) + 1
            text = f"Спикер {speaker_nums[speaker]}: {text}"
        lines.append(str(i))
        lines.append(f"{_fmt_time(seg['start'])} --> {_fmt_time(seg['end'])}")
        lines.append(text)
        lines.append("")
    return "\n".join(lines) + "\n"


def _render_json(result):
    keys = ["text", "segments", "engines", "fallback", "warnings"]
    payload = {k: result[k] for k in keys}
    return json.dumps(payload, ensure_ascii=False, indent=2)


def render(result, fmt="txt"):
    if fmt == "srt":
        return _render_srt(result)
    if fmt == "json":
        return _render_json(result)
    return result["text"]
