#!/usr/bin/env python3
"""Keep local manifests aligned with the pinned upstream dependency matrix.

The locked RVC source publishes separate Python 3.12 requirements for CPU,
CUDA 11.8, and CUDA 12.8. Start from those exact direct dependency sets and
apply only the necessary downstream deviations documented below. Any other
name or version drift fails the flake check.
"""

import re
import sys
import tomllib
from pathlib import Path


_NAME_RE = re.compile(r"[A-Za-z0-9._-]+")

MANIFESTS = {
    "cpu": Path("python/cpu/pyproject.toml"),
    "cuda118": Path("python/cuda118/pyproject.toml"),
    "cuda128": Path("python/cuda128/pyproject.toml"),
}

UPSTREAM_REQUIREMENTS = {
    "cpu": "requirments_cpu_py312.txt",
    "cuda118": "requirments_cu118_py312.txt",
    "cuda128": "requirments_cu128_py312.txt",
}

# The source tree vendors these exact packages. Installing the PyPI copies
# duplicates their modules and introduces a second, conflicting Torch policy.
VENDORED = {"pymss", "pymss-core"}

# Torch already owns the complete CUDA 11 dependency closure. Upstream pins a
# second cuDNN generation for ONNX Runtime GPU, which cannot coexist with
# Torch 2.7's cuDNN 9 package under one Python package name.
CUDA118_TORCH_OWNED = {
    "nvidia-cublas-cu11",
    "nvidia-cuda-nvrtc-cu11",
    "nvidia-cuda-runtime-cu11",
    "nvidia-cudnn-cu11",
    "nvidia-cufft-cu11",
}

# These are the only accepted edits to the dependency specifications obtained
# from upstream. Values of None remove an upstream dependency; strings replace
# or add one. CUDA Torch/Torchaudio are documented as a separate first install
# stage upstream, so they do not appear as ordinary requirement lines there.
DEVIATIONS: dict[str, dict[str, str | None]] = {
    "cpu": {
        # Torch 2.4.1 is below the CVE-2025-32434 fix. Keep the CPU variant on
        # the hardware-tested 2.7.1 family and match Torchvision accordingly.
        "torch": "torch==2.7.1",
        "torchaudio": "torchaudio==2.7.1",
        "torchvision": "torchvision==0.22.1",
    },
    "cuda118": {
        **{name: None for name in CUDA118_TORCH_OWNED},
        "onnxruntime-gpu": None,
        # RVC uses ONNX only for DirectML. Retain a CPU provider for diagnostics
        # without loading the upstream cuDNN 8 provider beside Torch's cuDNN 9.
        "onnxruntime": "onnxruntime>=1.24.4,<2",
        "torch": "torch==2.7.1",
        "torchaudio": "torchaudio==2.7.1",
    },
    "cuda128": {
        "torch": "torch==2.7.1",
        "torchaudio": "torchaudio==2.7.1",
    },
}


def canonical_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def canonical_spec(spec: str) -> str:
    """Normalize spelling that does not change a requirement's meaning."""
    match = _NAME_RE.match(spec)
    if not match:
        raise ValueError(f"cannot parse dependency {spec!r}")
    name = canonical_name(match.group(0))
    suffix = spec[match.end() :].replace('"', "'")
    return name + suffix


def load_manifest(path: Path) -> tuple[str, dict[str, str]]:
    with path.open("rb") as handle:
        project = tomllib.load(handle)["project"]
    dependencies = {
        canonical_name(_NAME_RE.match(spec).group(0)): canonical_spec(spec)
        for spec in project.get("dependencies", [])
    }
    return project["requires-python"], dependencies


def load_requirements(path: Path) -> dict[str, str]:
    dependencies: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", "-")):
            continue
        match = _NAME_RE.match(line)
        if not match:
            raise SystemExit(f"{path}: cannot parse requirement {line!r}")
        dependencies[canonical_name(match.group(0))] = canonical_spec(line)
    return dependencies


def expected_dependencies(variant: str, upstream_root: Path) -> dict[str, str]:
    expected = load_requirements(upstream_root / UPSTREAM_REQUIREMENTS[variant])
    for name in VENDORED:
        expected.pop(name, None)
    for name, replacement in DEVIATIONS[variant].items():
        if replacement is None:
            expected.pop(name, None)
        else:
            expected[name] = canonical_spec(replacement)
    return expected


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} REPO_ROOT UPSTREAM_ROOT")
    repo_root = Path(sys.argv[1])
    upstream_root = Path(sys.argv[2])

    failures: list[str] = []
    requires_python: dict[str, str] = {}
    counts: dict[str, int] = {}

    for variant, relative_manifest in MANIFESTS.items():
        manifest = repo_root / relative_manifest
        python_spec, actual = load_manifest(manifest)
        expected = expected_dependencies(variant, upstream_root)
        requires_python[variant] = python_spec
        counts[variant] = len(actual)

        for name in sorted(set(expected) - set(actual)):
            failures.append(f"{variant}: missing upstream dependency {expected[name]!r}")
        for name in sorted(set(actual) - set(expected)):
            failures.append(f"{variant}: undocumented local dependency {actual[name]!r}")
        for name in sorted(set(actual) & set(expected)):
            if actual[name] != expected[name]:
                failures.append(
                    f"{variant}: {name} is {actual[name]!r}, expected {expected[name]!r}"
                )

    if len(set(requires_python.values())) != 1:
        failures.append(f"requires-python differs: {requires_python}")

    if failures:
        raise SystemExit("pyproject manifests drifted:\n  " + "\n  ".join(failures))

    summary = ", ".join(f"{name}={counts[name]}" for name in MANIFESTS)
    print(f"pyproject manifests match pinned upstream plus documented deviations: {summary}")


if __name__ == "__main__":
    main()
