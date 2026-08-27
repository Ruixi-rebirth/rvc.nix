#!/usr/bin/env python3
"""Keep immutable upstream README links aligned with flake.lock."""

import json
import re
import sys
from pathlib import Path


LINK_PATTERN = re.compile(
    r"github\.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/blob/"
    r"([0-9a-f]{40})/"
)


def main(argv: list[str]) -> None:
    if len(argv) != 2:
        raise SystemExit(f"usage: {argv[0]} REPO_ROOT")

    repo_root = Path(argv[1])
    lock = json.loads((repo_root / "flake.lock").read_text(encoding="utf-8"))
    root_node = lock["nodes"][lock["root"]]
    rvc_node_name = root_node["inputs"]["rvc-src"]
    revision = lock["nodes"][rvc_node_name]["locked"]["rev"]

    failures = []
    for name in ("README.md", "README.zh-CN.md"):
        revisions = LINK_PATTERN.findall(
            (repo_root / name).read_text(encoding="utf-8")
        )
        if not revisions:
            failures.append(f"{name}: no immutable upstream link found")
        elif any(linked_revision != revision for linked_revision in revisions):
            failures.append(
                f"{name}: upstream link revisions are {revisions!r}, "
                f"expected {revision!r}"
            )

    if failures:
        raise SystemExit(
            "README links drifted from flake.lock:\n  " + "\n  ".join(failures)
        )

    print(f"README upstream links match rvc-src revision {revision}")


if __name__ == "__main__":
    main(sys.argv)
