import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent.parent
BIN = ROOT / "bin" / "transcribe"


def test_bin_help_from_tmp():
    res = subprocess.run(
        [str(BIN), "--help"],
        cwd="/tmp",
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0
