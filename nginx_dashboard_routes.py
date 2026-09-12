"""Fail-closed installer for dashboard routes in one NPM proxy-host config."""

from __future__ import annotations

import argparse
import pathlib
import re


BEGIN = "# BEGIN HH_MANAGED_ROUTES"
END = "# END HH_MANAGED_ROUTES"


def install_managed_routes(config: str, managed: str) -> str:
    if BEGIN in config:
        pattern = re.compile(
            rf"(?ms)^{re.escape(BEGIN)}.*?^{re.escape(END)}\s*(?=^  location / \{{)"
        )
    else:
        pattern = re.compile(r"(?ms)^# (?:Путь|Path) /hubapi/.*?(?=^  location / \{)")
    result, count = pattern.subn(managed.rstrip() + "\n\n", config, count=1)
    if count != 1:
        raise ValueError("legacy route anchor or managed block not found exactly once")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=pathlib.Path)
    parser.add_argument("managed", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    args.output.write_text(
        install_managed_routes(args.config.read_text(), args.managed.read_text())
    )


if __name__ == "__main__":
    main()
