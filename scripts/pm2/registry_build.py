#!/usr/bin/env python3
import argparse
import contextlib
import fcntl
import io
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
import traceback
from datetime import datetime, timezone

ENV_NAME = re.compile(r"[A-Z][A-Z0-9_]*")
TOKEN = re.compile(r"\b[A-Z][A-Z0-9_]*\b")
MISSING_SUFFIXES = (
    "_API_KEY", "_TOKEN", "_REFRESH_TOKEN", "_LOGIN", "_PASSWORD",
    "_SESSION", "_COOKIE", "_OTP_SEED", "_WEBHOOK",
    "_CLIENT_SECRET", "_CLIENT_ID", "_VALUE",
)
SKIP_DIRS = {".git", "node_modules", ".venv", ".agent-work", "__pycache__", "specs", ".beads", ".dolt", ".repowise-workspace", ".repowise", ".worktrees"}
STRAY_SKIP_DIRS = SKIP_DIRS | {"venv", "archives", "external-copies", ".pytest-tmp", ".snapshots", "letsencrypt", "ssl", "docker-data", "hiddify_data", "vendor", "site-packages", "testdata", "fastembed_cache", ".cc-home", ".venv-copier"}
STRAY_NAME = re.compile(r"^(?:\.env|\.env\..+|.*\.secrets\.env|\.secrets.*|\.netrc|.*\.pem|.*\.key|.*tokens.*\.json)$")
STRAY_EXAMPLE_SUFFIXES = (".example", ".template", ".sample", ".dist")
STRAY_SCAN_DIRS = ["/root/workspaces/projects", "/root/workspaces/tools", "/root/workspaces/sandbox", "/root/workspaces/system"]
REGISTRY_MD = "/root/workspaces/REGISTRY.md"
WORKSPACES = "/root/workspaces"
ZONES = ("services", "projects", "system/services", "acc1-legacy/services")
KNOWN_CONFLICTS = frozenset({"B24_WEBHOOK", "NPM_EMAIL", "OPENAI_API_KEY", "OPENROUTER_API_KEY"})

def read_allowlist(registry_md):
    try:
        with open(registry_md, encoding="utf-8", errors="replace") as handle:
            paths = re.findall(r"^\|\s*`([^`]+)`\s*\|", handle.read(), re.M)
    except FileNotFoundError:
        return set()
    return {os.path.abspath(path if os.path.isabs(path) else os.path.join(WORKSPACES, path))
            for path in paths}

def stray_scan(secrets, scan_dirs, allowlist):
    secrets = os.path.abspath(secrets)
    found = []
    for scan_dir in scan_dirs:
        if not os.path.isdir(scan_dir):
            continue
        for root, dirs, files in os.walk(scan_dir, followlinks=False):
            dirs[:] = [name for name in dirs if name not in STRAY_SKIP_DIRS]
            for filename in files:
                if not STRAY_NAME.fullmatch(filename) or filename.endswith(STRAY_EXAMPLE_SUFFIXES):
                    continue
                path = os.path.abspath(os.path.join(root, filename))
                if path in allowlist or path == secrets or path.startswith(secrets + os.sep):
                    continue
                if os.path.islink(path) and os.path.realpath(path).startswith(secrets + os.sep):
                    continue
                found.append(path)
    return sorted(found)

def quarantine(secrets, strays, enabled):
    marker = os.path.join(secrets, "quarantine", "ENABLED")
    counters = {"stray_secrets": len(strays), "quarantined": 0}
    if not enabled or not os.path.exists(marker):
        return counters
    quarantine_dir = os.path.dirname(marker)
    os.makedirs(quarantine_dir, mode=0o700, exist_ok=True)
    seen_path = os.path.join(quarantine_dir, "seen.json")
    try:
        with open(seen_path, encoding="utf-8") as handle:
            seen = json.load(handle)
    except (FileNotFoundError, ValueError):
        seen = {}
    for path in strays:
        try:
            metadata = os.lstat(path)
            if stat.S_ISLNK(metadata.st_mode):
                print("quarantine symlink skipped: " + path, file=sys.stderr)
                continue
            if not stat.S_ISREG(metadata.st_mode):
                continue
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            relative = path.removeprefix(WORKSPACES + os.sep).lstrip(os.sep)
            dest = os.path.join(quarantine_dir, timestamp, relative)
            os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
            os.replace(path, dest)
            os.chmod(dest, 0o600)
            open(path, "w").close()
            os.chmod(path, 0o600)
            with open(os.path.join(quarantine_dir, "log.jsonl"), "a", encoding="utf-8") as handle:
                handle.write(json.dumps({"ts": timestamp, "from": path, "to": dest}) + "\n")
            os.chmod(os.path.join(quarantine_dir, "log.jsonl"), 0o600)
            if path not in seen:
                seen[path] = timestamp
                with open(seen_path, "w", encoding="utf-8") as handle:
                    json.dump(seen, handle, sort_keys=True)
                os.chmod(seen_path, 0o600)
                # ponytail: без inotify — cron */10 достаточно, upgrade path: watchdog если понадобится минутная реакция.
                if not os.environ.get("REGISTRY_SELFTEST"):
                    subprocess.run(["bd", "create", "[CLAUDE] [STRAY-SECRET] " + path + " → карантин " + dest,
                                    "-p", "1"], cwd="/root/workspaces/projects", check=False,
                                   capture_output=True, timeout=30)
            counters["quarantined"] += 1
        except Exception:
            traceback.print_exc(file=sys.stderr)
    return counters

def stray_tools():
    config_paths = ["/root/.claude/settings.json", "/etc/claude-code/managed-settings.json",
                    "/root/.codex/hooks.json", "/root/workspaces/projects/.codex/hooks.json"]
    for directory in ("/root/workspaces/projects/.claude", "/root/.claude/skills"):
        if os.path.isdir(directory):
            for root, _, files in os.walk(directory, followlinks=False):
                config_paths.extend(os.path.join(root, name) for name in files
                                    if name.endswith((".json", ".md", ".sh")))
    found = set()
    pattern = re.compile(r"(/root/[A-Za-z0-9_./-]+\.(?:sh|py|js|mjs|cjs))")
    for path in config_paths:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                found.update(match for match in pattern.findall(handle.read())
                             if os.path.exists(match) and not match.startswith(("/root/workspaces/tools/", "/root/.claude/", "/root/.codex/")))
        except OSError:
            continue
    return sorted(found)

def parse_env_names(path):
    names = []
    violations = 0
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                violations += 1
                continue
            name = line[:line.index("=")].strip()
            if name.startswith("export "):
                name = name[7:].strip()
            if not ENV_NAME.fullmatch(name):
                violations += 1
                continue
            if name not in names:
                names.append(name)
    return names, violations

def read_manual(out):
    manual = {}
    service = None
    if not os.path.exists(out):
        return manual
    with open(out, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = re.match(r"^- service: (.+)$", line)
            if match:
                service = match.group(1)
                manual[service] = ["unknown", "unknown"]
                continue
            match = re.match(r"^  auth: (.+)$", line)
            if match and service:
                manual[service][0] = match.group(1)
                continue
            match = re.match(r"^  refresh: (.+)$", line)
            if match and service:
                manual[service][1] = match.group(1)
    return manual

def find_consumers(entries, scan_dirs, out):
    found = set()
    out_real = os.path.realpath(out)
    all_names = {name for entry in entries for name in entry["variables"]}
    name_to_entries = {}
    path_to_entry = {}
    for entry in entries:
        path_to_entry[entry["file"]] = entry
        for name in entry["variables"]:
            name_to_entries.setdefault(name, []).append(entry)
    names = re.compile(r"\b(?:" + "|".join(map(re.escape, sorted(all_names, key=len, reverse=True))) + r")\b") if all_names else None
    for scan_dir in scan_dirs:
        for root, dirs, files in os.walk(scan_dir, followlinks=False):
            dirs[:] = [name for name in dirs if name not in SKIP_DIRS and not os.path.islink(os.path.join(root, name))]
            for filename in files:
                path = os.path.join(root, filename)
                if (filename == "ENV-REGISTRY.yaml" or filename.endswith(".md") or os.path.islink(path) or
                        os.path.realpath(path) == out_real):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as handle:
                        head = handle.read(8192)
                        if b"\0" in head:
                            continue
                        data = head + handle.read()
                    text = data.decode("utf-8", errors="replace")
                except OSError:
                    continue
                by_path = [path_to_entry[path] for path in path_to_entry if path in text]
                by_name = [entry for name in set(names.findall(text)) for entry in name_to_entries[name]] if names else []
                for entry in {id(item): item for item in by_path + by_name}.values():
                    entry["consumers"].add(path)
                    found.add((entry["service"], path))
                candidates = {name for line in text.splitlines()
                              if not line.lstrip().startswith(("#", "//"))
                              for name in TOKEN.findall(line)
                              if name.endswith(MISSING_SUFFIXES) and name not in all_names}
                for entry in by_path:
                    entry["missing"].update(candidates)
    return len(found)

def yaml_list(items):
    return "[" + ", ".join(items) + "]"

def write_yaml(out, entries, files_scanned, strays=(), tools=()):
    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    lines = [
        "# generated by /root/workspaces/tools/scripts/pm2/registry_build.py — values never here",
        "# files_scanned: " + str(files_scanned),
    ]
    for entry in sorted(entries, key=lambda item: item["service"]):
        lines.extend([
            "- service: " + entry["service"],
            "  file: " + entry["file"],
            "  schema_violation: " + str(entry["schema_violation"]).lower(),
            "  variables: " + yaml_list(entry["variables"]),
            "  consumers: " + yaml_list(sorted(entry["consumers"])),
            "  missing: " + yaml_list(sorted(entry["missing"])),
            "  auth: " + entry["auth"],
            "  refresh: " + entry["refresh"],
        ])
    lines.extend(["stray_secrets: " + yaml_list(strays),
                  "stray_tools: " + yaml_list(tools)])
    text = "\n".join(lines) + "\n"
    # ponytail: без изменений не пишем — git не видит грязь.
    if os.path.exists(out) and open(out, encoding="utf-8").read() == text:
        return
    temp = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=os.path.dirname(os.path.abspath(out)) or ".", delete=False)
    try:
        with temp:
            temp.write(text)
            temp.flush()
        os.replace(temp.name, out)
    except BaseException:
        try:
            os.unlink(temp.name)
        except OSError:
            pass
        raise

def env_name(label, service, used=None):
    if ENV_NAME.fullmatch(label):
        name = label
    else:
        lowered = label.lower()
        rules = (
            ("_REFRESH_TOKEN", ("refresh",)),
            ("_CLIENT_SECRET", ("client secret", "client_secret", "secret", "секрет")),
            ("_CLIENT_ID", ("client id", "clientid", "client_id", "app id", "app_id")),
            ("_API_KEY", ("api key", "apikey", "api_key", "key", "ключ")),
            ("_PASSWORD", ("password", "pass", "пароль", "пасс")),
            ("_LOGIN", ("login", "username", "user", "email", "e-mail", "логин", "почта", "пользователь")),
            ("_WEBHOOK", ("webhook", "вебхук", "хук")),
            ("_COOKIE", ("cookie", "куки")),
            ("_SESSION", ("session", "сессия")),
            ("_OTP_SEED", ("otp", "2fa", "seed", "totp")),
            ("_TOKEN", ("personal access token", "token", "токен", "bearer", "pat", "access")),
            ("_URL", ("url", "host", "endpoint", "адрес", "домен", "domain")),
            ("_ID", ("id", "идентификатор")),
        )
        suffix, keywords = "_VALUE", ()
        for candidate, words in rules:
            if any(word in lowered for word in words):
                suffix, keywords = candidate, words
                break
        words = re.findall(r"[a-z0-9]+", lowered)
        keyword_words = {part for keyword in keywords for part in re.findall(r"[a-z0-9]+", keyword)}
        middle = [word for word in words if word not in keyword_words]
        prefix = service.upper().replace("-", "_")
        name = prefix + ("_" + "_".join(middle).upper() if middle else "") + suffix
    if used is None:
        return name
    candidate, number = name, 2
    while candidate in used:
        candidate = name + "_" + str(number)
        number += 1
    used.add(candidate)
    return candidate

def parse_raw(text, service):
    values, used, unparsed = {}, set(), 0
    try:
        decoded = json.loads(text)
    except (ValueError, TypeError):
        decoded = None
    if isinstance(decoded, dict):
        def flatten(value, label=""):
            nonlocal unparsed
            if isinstance(value, dict):
                for key, child in value.items():
                    flatten(child, (label + "_" if label else "") + str(key))
            elif isinstance(value, (str, int, float)) and not isinstance(value, bool):
                value = str(value).strip()
                if "\n" in value or "\r" in value:
                    unparsed += 1
                elif value:
                    values[env_name(label, service, used)] = value
        flatten(decoded)
        return values, unparsed
    pending = None
    def flush_pending():
        nonlocal pending, unparsed
        if pending is not None:
            unparsed += 1
            pending = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        positions = [pos for pos in (line.find("="), line.find(":")) if pos >= 0]
        if positions:
            flush_pending()
            pos = min(positions)
            label, value = line[:pos].strip(), line[pos + 1:].strip().strip("\"'")
            if not label or not value:
                unparsed += 1
            else:
                values[env_name(label, service, used)] = value
            continue
        token = len(line) >= 16 and not any(char.isspace() for char in line)
        if token:
            label = pending if pending is not None else "token"
            pending = None
            values[env_name(label, service, used)] = line
        else:
            flush_pending()
            pending = line if len(line) <= 40 else None
            if pending is None:
                unparsed += 1
    flush_pending()
    return values, unparsed

def merge_env(path, values):
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    os.chmod(parent, 0o700)
    lines = []
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    remaining = dict(values)
    merged = []
    for line in lines:
        match = re.match(r"^(?:export\s+)?([A-Z][A-Z0-9_]*)=", line)
        if match and match.group(1) in remaining:
            merged.append(match.group(1) + "=" + shell_quote(remaining.pop(match.group(1))))
        else:
            merged.append(line)
    merged.extend(name + "=" + shell_quote(value) for name, value in remaining.items())
    fd, temp = tempfile.mkstemp(dir=os.path.dirname(path), text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(merged) + "\n")
            handle.flush()
        os.replace(temp, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            os.unlink(temp)
        except OSError:
            pass
        raise

def shell_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def intake(secrets):
    inbox = os.path.join(secrets, "inbox")
    done = os.path.join(inbox, "done")
    os.makedirs(inbox, mode=0o700, exist_ok=True)
    os.makedirs(done, mode=0o700, exist_ok=True)
    os.chmod(inbox, 0o700)
    os.chmod(done, 0o700)
    counters = {"intake_files": 0, "intake_names": 0, "intake_unparsed": 0,
                "intake_skipped": 0, "intake_errors": 0}
    lock_fd = os.open(os.path.join(inbox, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("intake locked, skip")
            return counters
        for filename in sorted(os.listdir(inbox)):
            path = os.path.join(inbox, filename)
            if filename.startswith(".") or filename == "done":
                continue
            try:
                metadata = os.lstat(path)
            except OSError:
                counters["intake_skipped"] += 1
                continue
            if (not stat.S_ISREG(metadata.st_mode) or
                    metadata.st_uid != os.getuid() or metadata.st_mode & 0o077):
                counters["intake_skipped"] += 1
                continue
            stem, extension = os.path.splitext(filename)
            service = stem.lower().replace(" ", "-").replace("_", "-")
            if not re.fullmatch(r"[a-z0-9-]+", service):
                counters["intake_skipped"] += 1
                continue
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    values, unparsed = parse_raw(handle.read(), service)
                if unparsed:
                    counters["intake_unparsed"] += unparsed
                    print("intake service=" + service + " unparsed=" + str(unparsed) + " skipped")
                    continue
                merge_env(os.path.join(secrets, "services", service + ".env"), values)
                timestamp = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
                destination = os.path.join(done, service + "-" + timestamp + extension)
                os.replace(path, destination)
                os.chmod(destination, 0o600)
                counters["intake_files"] += 1
                counters["intake_names"] += len(values)
                print("intake service=" + service + " names=" + yaml_list(sorted(values)) + " unparsed=0")
            except Exception:
                counters["intake_errors"] += 1
                traceback.print_exc(file=sys.stderr)
    finally:
        os.close(lock_fd)
    return counters

def build(secrets, out, scan_dirs):
    started = time.monotonic()
    manual = read_manual(out)
    if not os.path.isdir(secrets):
        raise FileNotFoundError(secrets)
    intake_counters = intake(secrets)
    entries = []
    files_scanned = symlinks_skipped = schema_violation_files = schema_violation_lines = 0
    for root, dirs, files in os.walk(secrets, followlinks=False):
        dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(root, name))]
        for filename in files:
            if not filename.endswith(".env"):
                continue
            path = os.path.join(root, filename)
            if os.path.islink(path):
                symlinks_skipped += 1
                continue
            files_scanned += 1
            name = filename[:-4]
            service = name if not any(entry["service"] == name for entry in entries) else name + "@" + os.path.basename(root)
            variables, violations = parse_env_names(path)
            zone = os.path.relpath(root, secrets).replace(os.sep, "/")
            bad_file = zone not in ZONES
            schema_violation_files += int(bad_file)
            schema_violation_lines += violations
            auth, refresh = manual.get(service, ("unknown", "unknown"))
            entries.append({"service": service, "file": os.path.abspath(path), "schema_violation": bad_file,
                            "variables": variables, "consumers": set(), "missing": set(),
                            "auth": auth, "refresh": refresh})
    consumers_found = find_consumers(entries, scan_dirs, out)
    allowlist = read_allowlist(REGISTRY_MD)
    strays = stray_scan(secrets, STRAY_SCAN_DIRS, allowlist)
    quarantine_counters = quarantine(secrets, strays, True)
    tools = stray_tools()
    name_counts = {}
    for entry in entries:
        for name in entry["variables"]:
            name_counts[name] = name_counts.get(name, 0) + 1
    unknown_conflicts = sorted(name for name, count in name_counts.items()
                               if count > 1 and name not in KNOWN_CONFLICTS)
    if unknown_conflicts:
        print("unknown name conflict: " + unknown_conflicts[0], file=sys.stderr)
        sys.exit(2)
    counters = {"files_scanned": files_scanned, "entries_written": len(entries),
                "symlinks_skipped": symlinks_skipped, "schema_violation_files": schema_violation_files,
                "schema_violation_lines": schema_violation_lines, "consumers_found": consumers_found,
                "missing_total": sum(len(entry["missing"]) for entry in entries),
                "name_conflicts": sum(count > 1 for count in name_counts.values()),
                "stray_tools": len(tools),
                "duration_s": time.monotonic() - started, "_entries": entries,
                **intake_counters, **quarantine_counters}
    write_yaml(out, entries, files_scanned, strays, tools)
    return counters

def selftest():
    assert shell_quote("back\\slash and ' quote") == "'back\\slash and '\"'\"' quote'"
    original_stray_dirs = STRAY_SCAN_DIRS[:]
    STRAY_SCAN_DIRS[:] = []
    with tempfile.TemporaryDirectory() as base:
        secrets = os.path.join(base, "secrets")
        services = os.path.join(secrets, "services")
        projects = os.path.join(secrets, "projects")
        scan = os.path.join(base, "scan")
        out = os.path.join(base, "out", "registry.yaml")
        os.makedirs(services)
        os.makedirs(projects)
        os.makedirs(scan)
        os.makedirs(os.path.join(scan, ".worktrees", "copy"))
        stray_dir = os.path.join(base, "strays")
        os.makedirs(stray_dir)
        stray = os.path.join(stray_dir, ".env")
        example = os.path.join(stray_dir, ".env.example")
        allowed = os.path.join(stray_dir, "allowed.secrets.env")
        with open(stray, "w", encoding="utf-8") as handle:
            handle.write("test")
        open(example, "w").close()
        open(allowed, "w").close()
        linked_secret = os.path.join(secrets, "linked-secret")
        open(linked_secret, "w").close()
        os.symlink(linked_secret, os.path.join(stray_dir, ".env.link"))
        found_strays = stray_scan(secrets, [stray_dir], {allowed})
        assert found_strays == [stray]
        assert quarantine(secrets, found_strays, True) == {"stray_secrets": 1, "quarantined": 0}
        assert os.path.exists(stray)
        quarantine_dir = os.path.join(secrets, "quarantine")
        os.makedirs(quarantine_dir)
        open(os.path.join(quarantine_dir, "ENABLED"), "w").close()
        previous_selftest = os.environ.get("REGISTRY_SELFTEST")
        os.environ["REGISTRY_SELFTEST"] = "1"
        try:
            quarantined = quarantine(secrets, found_strays, True)
        finally:
            if previous_selftest is None:
                del os.environ["REGISTRY_SELFTEST"]
            else:
                os.environ["REGISTRY_SELFTEST"] = previous_selftest
        assert quarantined == {"stray_secrets": 1, "quarantined": 1} and os.path.getsize(stray) == 0
        dated_dirs = [name for name in os.listdir(quarantine_dir) if name != "ENABLED"]
        assert any(os.path.isfile(os.path.join(quarantine_dir, name, stray.lstrip(os.sep))) for name in dated_dirs)
        with open(os.path.join(quarantine_dir, "log.jsonl"), encoding="utf-8") as handle:
            assert len(handle.readlines()) == 1
        with open(os.path.join(quarantine_dir, "seen.json"), encoding="utf-8") as handle:
            assert stray in json.load(handle)
        for name in dated_dirs:
            moved = os.path.join(quarantine_dir, name, stray.lstrip(os.sep))
            if os.path.isfile(moved):
                os.unlink(moved)
                break
        inbox = os.path.join(secrets, "inbox")
        os.makedirs(inbox)
        figma_token = "EXAMPLE-FIGMA-ACCESS-VALUE"
        figma_password = "EXAMPLE-PASSWORD-VALUE"
        with open(os.path.join(inbox, "figma.txt"), "w", encoding="utf-8") as handle:
            handle.write("Personal access token\n" + figma_token + "\nEmail: user@example.com\nПароль: " + figma_password + "\nwebhook = https://hooks.example.com/x\n# comment\n")
        with open(os.path.join(inbox, "slack.json"), "w", encoding="utf-8") as handle:
            handle.write('{"bot_token":"EXAMPLE-NOT-A-REAL-TOKEN","app":{"client_secret":"EXAMPLE-NOT-A-REAL-SECRET","password":"pa$$word"}}')
        with open(os.path.join(inbox, "Bad Name!.txt"), "w", encoding="utf-8") as handle:
            handle.write("ignored")
        with open(os.path.join(inbox, "unparsed.txt"), "w", encoding="utf-8") as handle:
            handle.write("какая-то фраза без метки")
        for filename in ("figma.txt", "slack.json", "Bad Name!.txt", "unparsed.txt"):
            os.chmod(os.path.join(inbox, filename), 0o600)
        with open(os.path.join(services, "alpha.env"), "w", encoding="utf-8") as handle:
            handle.write("ALPHA_API_KEY=secretval1\nexport ALPHA_TOKEN=secretval2\n# comment\nbad line\nlower=1\n")
        with open(os.path.join(scan, ".worktrees", "copy", "ENV-REGISTRY.yaml"), "w", encoding="utf-8") as handle:
            handle.write(os.path.join(services, "alpha.env") + "\nMODEL_ID\nAWS_ACCESS_KEY_ID\n")
        with open(os.path.join(secrets, "beta.env"), "w", encoding="utf-8") as handle:
            handle.write("BETA_TOKEN=secretval3\n")
        with open(os.path.join(projects, "gamma.env"), "w", encoding="utf-8") as handle:
            handle.write("GAMMA_TOKEN=secretval4\n")
        os.symlink(os.path.join(services, "alpha.env"), os.path.join(services, "link.env"))
        consumer = os.path.join(scan, "consumer.sh")
        other = os.path.join(scan, "other.py")
        with open(consumer, "w", encoding="utf-8") as handle:
            handle.write(os.path.join(services, "alpha.env") + " ALPHA_API_KEY X_MISSING_TOKEN X_CLIENT_ID BETA_TOKEN BASE_URL GORSE_URL LLM_REQUEST_ID OPENROUTER_BASE_URL HOME\n# MODEL_ID AWS_ACCESS_KEY_ID\n// COMMENT_TOKEN")
        with open(other, "w", encoding="utf-8") as handle:
            handle.write("BETA_TOKEN")
        with open(os.path.join(scan, "note.md"), "w", encoding="utf-8") as handle:
            handle.write("ALPHA_API_KEY")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            first = build(secrets, out, [scan])
        entries = {entry["service"]: entry for entry in first["_entries"]}
        assert first["files_scanned"] == 5 and first["symlinks_skipped"] == 1
        assert first["schema_violation_files"] == 1 and first["schema_violation_lines"] == 2
        assert first["intake_files"] == 2 and first["intake_names"] == 7 and first["intake_unparsed"] == 1
        assert first["intake_skipped"] == 1 and first["intake_errors"] == 0
        assert entries["figma"]["variables"] == ["FIGMA_TOKEN", "FIGMA_LOGIN", "FIGMA_PASSWORD", "FIGMA_WEBHOOK"]
        assert entries["slack"]["variables"] == ["SLACK_BOT_TOKEN", "SLACK_APP_CLIENT_SECRET", "SLACK_APP_PASSWORD"]
        figma_env = os.path.join(services, "figma.env")
        slack_env = os.path.join(services, "slack.env")
        assert os.stat(figma_env).st_mode & 0o777 == 0o600
        assert os.stat(services).st_mode & 0o777 == 0o700
        assert os.listdir(os.path.join(inbox, "done")) and not os.path.exists(os.path.join(inbox, "figma.txt"))
        assert os.path.exists(os.path.join(inbox, "unparsed.txt")) and not os.path.exists(os.path.join(services, "unparsed.env"))
        with open(figma_env, encoding="utf-8") as handle:
            figma_text = handle.read()
        with open(slack_env, encoding="utf-8") as handle:
            slack_text = handle.read()
        assert "FIGMA_TOKEN='" + figma_token + "'" in figma_text and "FIGMA_PASSWORD='" + figma_password + "'" in figma_text
        assert "SLACK_APP_PASSWORD='pa$$word'" in slack_text
        assert entries["alpha"]["variables"] == ["ALPHA_API_KEY", "ALPHA_TOKEN"]
        assert sorted(entries["alpha"]["consumers"]) == [consumer]
        assert sorted(entries["alpha"]["missing"]) == ["X_CLIENT_ID", "X_MISSING_TOKEN"]
        assert sorted(entries["beta"]["consumers"]) == [consumer, other] and not entries["beta"]["missing"]
        assert entries["gamma"]["schema_violation"] is False
        assert first["name_conflicts"] == 0 and entries["alpha"]["auth"] == entries["alpha"]["refresh"] == "unknown"
        with open(out, encoding="utf-8") as handle:
            text = handle.read()
        assert "stray_secrets: [" in text and "stray_tools: [" in text
        assert not any(value in text or value in output.getvalue() for value in ("secretval1", "secretval2", "secretval3", "secretval4", figma_token, figma_password))
        assert re.search(r"^\s*[A-Z][A-Z0-9_]*=", text, re.M) is None
        text = text.replace("- service: alpha\n", "- service: alpha\n", 1).replace("  auth: unknown\n  refresh: unknown\n", "  auth: api_key\n  refresh: static\n", 1)
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.unlink(os.path.join(secrets, "beta.env"))
        with contextlib.redirect_stdout(io.StringIO()):
            second = build(secrets, out, [scan])
        entries = {entry["service"]: entry for entry in second["_entries"]}
        assert second["entries_written"] == 4 and "beta" not in entries
        assert entries["alpha"]["auth"] == "api_key" and entries["alpha"]["refresh"] == "static"
        with open(os.path.join(inbox, "figma.txt"), "w", encoding="utf-8") as handle:
            handle.write("Personal access token\nEXAMPLE-NEW-FIGMA-VALUE\n")
        os.chmod(os.path.join(inbox, "figma.txt"), 0o600)
        with contextlib.redirect_stdout(io.StringIO()):
            third = build(secrets, out, [scan])
        with open(figma_env, encoding="utf-8") as handle:
            figma_text = handle.read()
        assert "EXAMPLE-NEW-FIGMA-VALUE" in figma_text and "FIGMA_LOGIN='user@example.com'" in figma_text
        assert {entry["service"] for entry in third["_entries"]} >= {"figma", "slack"}
        with open(os.path.join(inbox, "newline.json"), "w", encoding="utf-8") as handle:
            handle.write('{"token":"one\\ntwo"}')
        os.chmod(os.path.join(inbox, "newline.json"), 0o600)
        insecure = os.path.join(inbox, "insecure.txt")
        with open(insecure, "w", encoding="utf-8") as handle:
            handle.write("token=ignored")
        os.chmod(insecure, 0o644)
        symlink = os.path.join(inbox, "symlink.txt")
        os.symlink(insecure, symlink)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            secured = build(secrets, out, [scan])
        assert secured["intake_skipped"] == 3 and secured["intake_unparsed"] == 2
        assert os.path.exists(insecure) and os.path.islink(symlink)
        assert os.path.exists(os.path.join(inbox, "newline.json"))
        assert "intake service=newline unparsed=1 skipped" in output.getvalue()
        with open(os.path.join(services, "duplicate.env"), "w", encoding="utf-8") as handle:
            handle.write("ALPHA_TOKEN=x\n")
        before_conflict = open(out, "rb").read()
        error_output = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(error_output):
                build(secrets, out, [scan])
            assert False
        except SystemExit as error:
            assert error.code == 2
        assert "unknown name conflict: ALPHA_TOKEN" in error_output.getvalue()
        assert open(out, "rb").read() == before_conflict
        before = open(out, "rb").read()
        mtime = os.stat(out).st_mtime_ns
        try:
            build(os.path.join(base, "missing"), out, [scan])
            assert False
        except FileNotFoundError:
            pass
        assert open(out, "rb").read() == before and os.stat(out).st_mtime_ns == mtime
    STRAY_SCAN_DIRS[:] = original_stray_dirs
    print("selftest ok")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--secrets", default="/root/workspaces/secrets")
    parser.add_argument("--out", default="/root/workspaces/projects/docs/ENV-REGISTRY.yaml")
    parser.add_argument("--scan", nargs="+", default=["/root/workspaces/tools", "/root/workspaces/projects"])
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return 0
    counters = build(args.secrets, args.out, args.scan)
    print(" ".join(key + "=" + (format(value, ".2f") if key == "duration_s" else str(value))
                   for key, value in counters.items() if not key.startswith("_")))
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        traceback.print_exc()
        sys.exit(1)
