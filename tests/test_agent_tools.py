import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "acc1-scripts"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AgentToolsTest(unittest.TestCase):
    def test_download_backends_are_siblings(self):
        text = (SCRIPTS / "agent-download.sh").read_text()
        self.assertIn('$SCRIPT_DIR/gdrive-download.sh', text)
        self.assertIn('$SCRIPT_DIR/b244-fetch.sh', text)
        self.assertTrue((SCRIPTS / "gdrive-download.sh").is_file())
        self.assertTrue((SCRIPTS / "b244-fetch.sh").is_file())

    def test_google_expiry_accepts_epoch_and_iso(self):
        module = load("gdrive_download", SCRIPTS / "gdrive-download.py")
        self.assertEqual(module.parse_expiry(123), 123)
        self.assertEqual(module.parse_expiry("1970-01-01T00:02:03Z"), 123)
        self.assertEqual(module.parse_expiry("invalid"), 0)

    def test_assembly_result_has_word_timestamps(self):
        module = load("assemblyai_transcribe", SCRIPTS / "assemblyai-transcribe.py")
        transcript = SimpleNamespace(
            text="hello",
            words=[SimpleNamespace(text="hello", start=10, end=20, confidence=0.9)],
        )
        self.assertEqual(module.result_payload(transcript)["words"][0]["start_ms"], 10)

    def test_missing_assembly_key_is_redacted(self):
        module = load("assemblyai_transcribe_no_key", SCRIPTS / "assemblyai-transcribe.py")
        old = os.environ.pop("ASSEMBLYAI_API_KEY", None)
        module.SECRET_FILE = Path("/definitely/missing")
        try:
            with self.assertRaisesRegex(RuntimeError, "ASSEMBLYAI_API_KEY is not set"):
                module.api_key()
        finally:
            if old is not None:
                os.environ["ASSEMBLYAI_API_KEY"] = old

    def test_shell_syntax(self):
        for script in ("agent-download.sh", "gdrive-download.sh", "google-token-refresh.sh", "share-file.sh"):
            subprocess.run(["bash", "-n", SCRIPTS / script], check=True)


if __name__ == "__main__":
    unittest.main()
