from transcribe.keys import load_key, redact


class EngineError(Exception):
    def __init__(self, *, engine, status, retry_after, message):
        self.engine = engine
        self.status = status
        self.retry_after = retry_after
        self.message = message
        super().__init__(message)

    def __str__(self):
        return self.message


class GroqEngine:
    name = "groq"
    model = "whisper-large-v3"
    key_name = "GROQ_API_KEY"
    key_file = "/root/workspaces/secrets/projects/client-video-transcription/.env"

    def transcribe(self, path, lang, speakers=False):
        from groq import Groq

        try:
            client = Groq(api_key=load_key(self.key_name, self.key_file, "groq"), timeout=120)
            with open(path, "rb") as f:
                r = client.audio.transcriptions.create(
                    file=f,
                    model=self.model,
                    language=lang,
                    response_format="verbose_json",
                )
            segs = getattr(r, "segments", None) or []
            segments = []
            for seg in segs:
                item = seg if isinstance(seg, dict) else seg.__dict__
                segments.append(
                    {
                        "start": item["start"],
                        "end": item["end"],
                        "text": item["text"],
                    }
                )
            return {"text": r.text.strip(), "segments": segments}
        except Exception as e:
            headers = getattr(e, "response", None)
            headers = getattr(headers, "headers", None) if headers is not None else None
            retry_after = None
            if headers is not None:
                raw = headers.get("retry-after")
                if raw is not None:
                    try:
                        retry_after = int(raw)
                    except (TypeError, ValueError):
                        retry_after = None
            raise EngineError(
                engine="groq",
                status=getattr(e, "status_code", None),
                retry_after=retry_after,
                message=redact(str(e)),
            ) from e
