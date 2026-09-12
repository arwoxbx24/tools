"""Offline regression for response lifetime; no provider requests."""
from pathlib import Path
import subprocess

source = Path(__file__).with_name("failover.sh").read_text()
capture = source.split("  ) || gate_rc=$?\n", 1)[1].split(
    "  local gate reason finish pt ct cost", 1
)[0]
for status, expected in (("GATE_OK", "response"), ("GATE_FAIL", "")):
    script = """set -euo pipefail
CONTENT_FILE=$(mktemp /tmp/or-content-XXXXXX)
tmpbody=$(mktemp /tmp/or-body-XXXXXX)
printf response > "$CONTENT_FILE"
gate_rc=0
model=test
latency=0
log_receipt() { :; }
"""
    script += "gate_out=" + status + "$'\\tstop'\n" + capture
    script += '\n[[ "$CONTENT" == ' + repr(expected) + ' ]]\n'
    script += '[[ ! -e "$CONTENT_FILE" && ! -e "$tmpbody" ]]\n'
    subprocess.run(["bash", "-c", script], check=True)
print("Response lifetime: success and rejection passed")
