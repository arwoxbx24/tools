from transcribe.keys import load_key, redact

from .groq_engine import EngineError


class AssemblyAIEngine:
    name = "assemblyai"
    model = "universal-3-5-pro,universal-2"
    key_name = "ASSEMBLYAI_API_KEY"
    key_file = "/root/workspaces/secrets/services/assemblyai.env"

    def transcribe(self, path, lang, speakers=False):
        import assemblyai as aai

        try:
            aai.settings.api_key = load_key(self.key_name, self.key_file, "assemblyai")
            config = aai.TranscriptionConfig(
                language_code=lang,
                speech_models=["universal-3-5-pro", "universal-2"],
                speaker_labels=speakers,
            )
            t = aai.Transcriber(config=config).transcribe(str(path))

            if t.status == aai.TranscriptStatus.error:
                raise EngineError(
                    engine="assemblyai",
                    status=None,
                    retry_after=None,
                    message=redact(str(t.error)),
                )

            utterances = t.utterances or []
            segments = [
                {
                    "start": u.start / 1000,
                    "end": u.end / 1000,
                    "text": u.text,
                    "speaker": u.speaker,
                }
                for u in utterances
            ]

            if speakers:
                number_by_letter = {}
                lines = []
                for u in utterances:
                    if u.speaker not in number_by_letter:
                        number_by_letter[u.speaker] = len(number_by_letter) + 1
                    lines.append(
                        f"Спикер {number_by_letter[u.speaker]}: {u.text}"
                    )
                text = "\n".join(lines)
            else:
                text = t.text

            warnings = []
            try:
                aai.Transcript.delete_by_id(t.id)
            except Exception:
                warnings.append(f"транскрипт {t.id} у AssemblyAI не удалён")

            return {"text": text, "segments": segments, "warnings": warnings}
        except Exception as e:
            if isinstance(e, EngineError):
                raise e
            raise EngineError(
                engine="assemblyai",
                status=getattr(e, "status_code", None),
                retry_after=None,
                message=redact(str(e)),
            ) from e
