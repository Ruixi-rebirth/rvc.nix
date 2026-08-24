#!/usr/bin/env python3
"""Keep the CPU and CUDA pyproject.toml dependency sets in sync.

uv2nix resolves CPU and CUDA as two separate workspaces because the PyTorch
indexes publish different wheel graphs, and each workspace needs its own
uv.lock. The manifests therefore cannot be merged into one file, but their
direct dependency sets must stay aligned except for the documented exceptions
below — otherwise an update to one manifest silently drifts from the other.

Run by `nix flake check` as checks.pyproject-sync.
"""

import re
import sys
import tomllib
from pathlib import Path

# Direct dependencies allowed to exist in the CPU manifest only, and why.
CPU_ONLY_ALLOWED = {
    # The CPU resolution pins it below 0.4.3; the CUDA resolution carries it
    # as a transitive dependency at a newer version, so adding the pin there
    # would invalidate the CUDA lock.
    "hyper-connections": "CPU pins <0.4.3; CUDA resolves it transitively",
}

_NAME_RE = re.compile(r"[A-Za-z0-9._-]+")


def load_dependencies(manifest: Path) -> tuple[str, dict[str, str]]:
    with manifest.open("rb") as handle:
        project = tomllib.load(handle)["project"]
    requires_python = project["requires-python"]
    deps: dict[str, str] = {}
    for spec in project.get("dependencies", []):
        match = _NAME_RE.match(spec)
        if not match:
            raise SystemExit(f"{manifest}: cannot parse dependency {spec!r}")
        deps[match.group(0)] = spec
    return requires_python, deps


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} REPO_ROOT")
    repo_root = Path(sys.argv[1])
    cuda_manifest = repo_root / "pyproject.toml"
    cpu_manifest = repo_root / "python/cpu/pyproject.toml"

    cuda_python, cuda_deps = load_dependencies(cuda_manifest)
    cpu_python, cpu_deps = load_dependencies(cpu_manifest)

    failures: list[str] = []

    if cuda_python != cpu_python:
        failures.append(
            f"requires-python differs: {cuda_python!r} (CUDA) vs {cpu_python!r} (CPU)"
        )

    for name in sorted(set(cuda_deps) & set(cpu_deps)):
        if cuda_deps[name] != cpu_deps[name]:
            failures.append(
                f"{name}: CUDA {cuda_deps[name]!r} vs CPU {cpu_deps[name]!r}"
            )

    for name in sorted(set(cpu_deps) - set(cuda_deps)):
        if name not in CPU_ONLY_ALLOWED:
            failures.append(
                f"{name}: CPU-only dependency without an allowlist entry"
            )

    for name in sorted(set(cuda_deps) - set(cpu_deps)):
        failures.append(
            f"{name}: CUDA-only dependency; every direct dependency must be shared"
        )

    if failures:
        raise SystemExit("pyproject manifests drifted:\n  " + "\n  ".join(failures))

    print(
        "pyproject manifests in sync: "
        f"{len(cuda_deps)} CUDA / {len(cpu_deps)} CPU direct dependencies"
    )


if __name__ == "__main__":
    main()
