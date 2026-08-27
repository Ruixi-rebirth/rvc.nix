#!/usr/bin/env python3
"""Require both usage guides to document every flake application."""

import json
import re
import sys
from pathlib import Path


NAMED_APP_PATTERN = re.compile(r"nix run \.#([a-z0-9-]+)")
DEFAULT_APP_PATTERN = re.compile(r"nix run \.(?![#a-z0-9_-])")
GUIDES = ("docs/usage.md", "docs/usage.zh-CN.md")


def main(argv: list[str]) -> None:
    if len(argv) != 3:
        raise SystemExit(f"usage: {argv[0]} REPO_ROOT APP_NAMES_JSON")

    repo_root = Path(argv[1])
    app_names = set(json.loads(Path(argv[2]).read_text(encoding="utf-8")))
    expected_named = app_names - {"default"}
    failures = []

    for relative_path in GUIDES:
        text = (repo_root / relative_path).read_text(encoding="utf-8")
        documented = set(NAMED_APP_PATTERN.findall(text))
        missing = sorted(expected_named - documented)
        unknown = sorted(documented - expected_named)

        if missing:
            failures.append(f"{relative_path}: missing apps {missing!r}")
        if unknown:
            failures.append(f"{relative_path}: unknown apps {unknown!r}")
        if "default" in app_names and not DEFAULT_APP_PATTERN.search(text):
            failures.append(f"{relative_path}: missing default `nix run .` app")

    if failures:
        raise SystemExit("Application documentation drifted:\n  " + "\n  ".join(failures))

    print(f"Application documentation matches all {len(app_names)} flake apps")


if __name__ == "__main__":
    main(sys.argv)
