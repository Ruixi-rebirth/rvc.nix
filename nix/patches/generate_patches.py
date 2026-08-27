#!/usr/bin/env python3
"""Regenerate the RVC source patches under nix/patches from the pinned upstream.

This script mirrors the patch pipeline of nix/package.nix exactly: apply
nix/patches/safe-training-subprocesses.patch (patchPhase), normalise the
mixed-line-ending Python patch inputs, then apply the base substitutions into
nix/patches/rvc/*.patch and the CUDA substitutions into
nix/patches/cuda/*.patch.

Patch files are numbered automatically from the ordered file lists in
rules.py; do not maintain numeric prefixes by hand.

The substitution rules live in rules.py, the data-driven transcription of the
substituteInPlace calls that used to live inline in nix/package.nix. Like
substituteInPlace, every rule replaces ALL occurrences of its find string and
is an error when nothing matches. Every generated patch starts with its
purpose and points back to this script and rules.py as its source of truth.

Before writing anything, the script verifies the generated patch files by
applying them to a clean upstream copy and byte-comparing the result, and by
re-running the project's own installCheck grep assertions and AST policy tests
against the patched tree. From the rvc.nix repository, the normal entry point
uses the source already locked into the Nix store:

    nix flake update rvc-src
    nix develop -c rvc-generate-patches

The Python CLI remains available for maintenance outside Nix:

    python nix/patches/generate_patches.py \
        --repo /path/to/Retrieval-based-Voice-Conversion-WebUI

The upstream tree is read from git objects (git archive), not from the
working tree, so host line-ending configuration can never corrupt the
result. Requires Python 3.12+.

CI runs the same pipeline against the pinned source without network (the
rvc-src flake input is already extracted at evaluation time) and requires
byte equality with the checked-in patch files:

    python nix/patches/generate_patches.py \
        --repo-root "$repo" --src-dir "$src" --verify
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid
from pathlib import Path

from rules import (
    BASE_GREPS,
    BASE_PATCH_DESCRIPTIONS,
    BASE_PATCH_FILES,
    BASE_RULES,
    CUDA_GREPS,
    CUDA_PATCH_DESCRIPTIONS,
    CUDA_PATCH_FILES,
    CUDA_RULES,
)

DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[2]
CRLF_PATCH_FILES = ("infer/hubert.py", "realtime_gui.py")
PATCH_NUMBER_STEP = 10


def make_patch_names(files: tuple[str, ...]) -> dict[str, str]:
    """Assign ordered numeric prefixes and readable names to patch files."""
    if len(set(files)) != len(files):
        raise SystemExit("patch file list contains duplicate source paths")
    number_width = max(3, len(str(len(files) * PATCH_NUMBER_STEP)))
    return {
        relative: (
            f"{index * PATCH_NUMBER_STEP:0{number_width}d}-"
            f"{Path(relative).with_suffix('').as_posix().replace('/', '-').replace('_', '-')}.patch"
        )
        for index, relative in enumerate(files, start=1)
    }


BASE_PATCH_NAMES = make_patch_names(BASE_PATCH_FILES)
CUDA_PATCH_NAMES = make_patch_names(CUDA_PATCH_FILES)


def read_locked_revision(repo_root: Path) -> str:
    lock = json.loads((repo_root / "flake.lock").read_text(encoding="utf-8"))
    return lock["nodes"]["rvc-src"]["locked"]["rev"]


def read_git_head(repo: Path) -> str:
    """Read the checked-out commit without spawning git (sandbox-friendly)."""
    head_file = repo / ".git" / "HEAD"
    head = head_file.read_text(encoding="utf-8").strip()
    if head.startswith("ref: "):
        ref_file = repo / ".git" / head[len("ref: ") :]
        return ref_file.read_text(encoding="utf-8").strip()
    return head


def run_git(repo: Path, *args: str) -> None:
    # core.autocrlf=false/eol=lf override host git config: git apply must
    # never rewrite line endings (GNU patch in the Nix build preserves them).
    subprocess.run(
        [
            "git",
            "-c",
            "core.autocrlf=false",
            "-c",
            "core.eol=lf",
            "-C",
            str(repo),
            *args,
        ],
        check=True,
    )


def apply_patch_file(repo: Path, patch_path: Path) -> None:
    run_git(repo, "apply", "--whitespace=nowarn", str(patch_path))


def materialize_git_tree(repo: Path, dst: Path) -> None:
    """Materialize the checked-out commit's blobs byte-faithfully.

    Reads git objects directly via `git archive` instead of copying the
    working tree, so host line-ending configuration (e.g. core.autocrlf=true
    on Windows) can never corrupt the source the patches are generated from.
    Only tracked files exist in the archive, which also drops untracked
    clutter from the maintenance checkout.
    """
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)
    archive_path = dst.parent / f"rvc-src-{uuid.uuid4().hex[:8]}.tar"
    with archive_path.open("wb") as handle:
        subprocess.run(
            # The -c overrides matter: on Windows, `git archive` honours
            # core.autocrlf and would convert the exported blobs to CRLF.
            [
                "git",
                "-c",
                "core.autocrlf=false",
                "-c",
                "core.eol=lf",
                "-C",
                str(repo),
                "archive",
                "--format=tar",
                "HEAD",
            ],
            stdout=handle,
            check=True,
        )
    try:
        with tarfile.open(archive_path) as tar:
            tar.extractall(dst, filter="data")
    finally:
        archive_path.unlink(missing_ok=True)


def materialize_directory(src_dir: Path, dst: Path) -> None:
    """Copy a plain directory tree of the upstream source byte-faithfully.

    Used by CI (checks.patches-in-sync) where the pinned rvc-src flake input
    is already a store path extracted from the byte-faithful GitHub tarball,
    so no git checkout exists or is needed.
    """
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src_dir, dst)
    # Store paths keep both directories and files read-only; patch
    # application and rule writes need writable copies of each.
    for path in [dst] + list(dst.rglob("*")):
        if path.is_file():
            path.chmod(0o644)
        elif path.is_dir():
            path.chmod(0o755)


def snapshot(root: Path) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            rel = str(path.relative_to(root)).replace(os.sep, "/")
            files[rel] = path.read_bytes()
    return files


def normalize_crlf(path: Path) -> None:
    content = path.read_bytes()
    content = content.replace(b"\r\n", b"\n")
    if content.endswith(b"\r"):
        content = content[:-1]
    path.write_bytes(content)


def normalize_patch_inputs(root: Path) -> None:
    """Normalise only mixed-line-ending files modified downstream."""
    for relative in CRLF_PATCH_FILES:
        normalize_crlf(root / relative)


def apply_rules(
    content: bytes, rules: list[tuple]
) -> tuple[bytes, list[tuple[str, str, int]]]:
    counts: list[tuple[str, str, int]] = []
    for rel, find, replace, description in rules:
        find_bytes = find.encode("utf-8")
        replace_bytes = replace.encode("utf-8")
        found = content.count(find_bytes)
        if found == 0:
            raise SystemExit(
                f"substitution no longer matches: {description!r} in {rel!r}"
            )
        content = content.replace(find_bytes, replace_bytes)
        counts.append((rel, description, found))
    return content, counts


def validate_patch_metadata(
    files: tuple[str, ...], descriptions: dict[str, str], rules: list[tuple], label: str
) -> None:
    declared = set(files)
    described = set(descriptions)
    ruled = {rule[0] for rule in rules}
    missing_descriptions = sorted(declared - described)
    extra_descriptions = sorted(described - declared)
    missing_rules = sorted(declared - ruled)
    undeclared_rules = sorted(ruled - declared)
    if missing_descriptions or extra_descriptions or missing_rules or undeclared_rules:
        details = []
        if missing_descriptions:
            details.append(
                "missing descriptions: " + ", ".join(missing_descriptions)
            )
        if extra_descriptions:
            details.append(
                "descriptions without patch files: "
                + ", ".join(extra_descriptions)
            )
        if missing_rules:
            details.append("patch files without rules: " + ", ".join(missing_rules))
        if undeclared_rules:
            details.append(
                "rules without patch files: " + ", ".join(undeclared_rules)
            )
        raise SystemExit(f"{label} patch metadata mismatch: " + "; ".join(details))


def generate_patch(
    rel_path: str, before: bytes, after: bytes, description: str
) -> bytes | None:
    if before == after:
        return None
    # difflib works on str; the upstream sources are UTF-8, so a strict
    # decode/encode round-trip is byte-exact.
    diff = difflib.unified_diff(
        before.decode("utf-8").splitlines(keepends=True),
        after.decode("utf-8").splitlines(keepends=True),
        fromfile=f"a/{rel_path}",
        tofile=f"b/{rel_path}",
        # Four context lines keep generated patches from ending on the two
        # blank lines between top-level Python definitions. Such a final
        # unified-diff context marker is valid, but git diff --check treats it
        # as trailing whitespace in the patch file itself.
        n=4,
    )
    header = (
        f"# Description: {description}\n"
        "# Generated-by: nix/patches/generate_patches.py\n"
        "# Source-of-truth: nix/patches/rules.py\n"
        "#\n"
    )
    patch = (header + "".join(diff)).encode("utf-8")
    return patch or None


def compare_trees(expected: dict[str, bytes], actual: Path) -> list[str]:
    problems: list[str] = []
    got = snapshot(actual)
    for rel in sorted(set(expected) | set(got)):
        if rel not in expected:
            problems.append(f"unexpected file after patch: {rel}")
        elif rel not in got:
            problems.append(f"missing file after patch: {rel}")
        elif expected[rel] != got[rel]:
            problems.append(f"content mismatch after patch: {rel}")
    return problems


def run_grep_checks(
    tree: dict[str, bytes], greps: list[tuple], label: str
) -> list[str]:
    failures: list[str] = []
    for rel, needle, must_exist in greps:
        content = tree.get(rel)
        needle_bytes = needle.encode("utf-8")
        present = content is not None and needle_bytes in content
        if must_exist and not present:
            failures.append(f"{label}: expected {needle!r} in {rel}")
        if not must_exist and present:
            failures.append(f"{label}: unexpected {needle!r} in {rel}")
    return failures


def run_project_tests(repo_root: Path, tree_root: Path) -> None:
    subprocess.run(
        [sys.executable, str(repo_root / "nix/tests/checkpoint_ast_policy.py"), str(tree_root)],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(repo_root / "nix/tests/training_subprocess_security.py"),
            str(tree_root / "webui.py"),
        ],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        type=Path,
        default=None,
        help="checkout of Retrieval-based-Voice-Conversion-WebUI",
    )
    parser.add_argument(
        "--src-dir",
        type=Path,
        default=None,
        help="plain directory with the upstream source (used by CI, where the "
        "pinned rvc-src flake input is already extracted); alternative to --repo",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="after generating and checking the patches, compare them "
        "byte-for-byte against nix/patches/{rvc,cuda} and exit non-zero on drift",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="verify only; do not write patch files into the repository",
    )
    parser.add_argument(
        "--scratch",
        type=Path,
        default=None,
        help="scratch directory (default: the system temp dir; use a writable "
        "tree such as the repository checkout when the temp dir is restricted)",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=DEFAULT_REPO_ROOT,
        help="rvc.nix repository root holding the checked-in patch files and "
        "tests (default: derived from this script's location; pass ${self} "
        "when the script runs from its store copy, as in checks.patches-in-sync)",
    )
    args = parser.parse_args()

    if not args.repo and not args.src_dir:
        raise SystemExit("provide --repo (a git checkout) or --src-dir (an extracted source tree)")

    repo_root = args.repo_root.resolve()
    safe_training_patch = repo_root / "nix/patches/safe-training-subprocesses.patch"

    validate_patch_metadata(
        BASE_PATCH_FILES, BASE_PATCH_DESCRIPTIONS, BASE_RULES, "base"
    )
    validate_patch_metadata(
        CUDA_PATCH_FILES, CUDA_PATCH_DESCRIPTIONS, CUDA_RULES, "CUDA"
    )

    if args.repo:
        if not (args.repo / ".git").exists():
            raise SystemExit(f"not a git checkout: {args.repo}")
        locked_rev = read_locked_revision(repo_root)
        head_rev = read_git_head(args.repo)
        if head_rev != locked_rev:
            print(
                f"NOTE: checkout HEAD {head_rev} differs from the flake.lock pin "
                f"{locked_rev}; this is expected when updating upstream."
            )
        else:
            print(f"upstream checkout matches the flake.lock pin: {head_rev}")

        def materialize(dst: Path) -> None:
            materialize_git_tree(args.repo, dst)

    else:
        print(f"upstream source tree: {args.src_dir}")

        def materialize(dst: Path) -> None:
            materialize_directory(args.src_dir, dst)

    scratch_root = args.scratch or Path(tempfile.gettempdir())
    # Create every directory with os.makedirs (never mkdtemp): some sandbox
    # policies only allow creating children of directories made by makedirs.
    scratch_root.mkdir(parents=True, exist_ok=True)
    scratch = scratch_root / f"rvc-patches-{uuid.uuid4().hex[:8]}"
    os.makedirs(scratch)
    work = scratch / "work"
    verify = scratch / "verify"
    temp_patches = scratch / "patches"
    os.makedirs(temp_patches)
    try:
        # Mirror the build order: byte-faithful tree, safe-training patch
        # (patchPhase), targeted CRLF normalisation, then the base and CUDA
        # substitutions.
        materialize(work)
        apply_patch_file(work, safe_training_patch)

        normalize_patch_inputs(work)
        snapshot_base = snapshot(work)

        base_counts: list[tuple[str, str, int]] = []
        for rel in BASE_PATCH_FILES:
            path = work / rel
            content, counts = apply_rules(
                path.read_bytes(), [rule for rule in BASE_RULES if rule[0] == rel]
            )
            base_counts.extend(counts)
            path.write_bytes(content)
        snapshot_cpu = snapshot(work)

        cuda_counts: list[tuple[str, str, int]] = []
        for rel in CUDA_PATCH_FILES:
            path = work / rel
            content, counts = apply_rules(
                path.read_bytes(), [rule for rule in CUDA_RULES if rule[0] == rel]
            )
            cuda_counts.extend(counts)
            path.write_bytes(content)
        snapshot_cuda = snapshot(work)

        # Generate per-file patches: base diffs against the pre-substitution
        # state, CUDA diffs against the post-base state, so both sets apply
        # in build order.
        base_patches: dict[str, bytes] = {}
        for rel in BASE_PATCH_FILES:
            patch = generate_patch(
                rel,
                snapshot_base[rel],
                snapshot_cpu[rel],
                BASE_PATCH_DESCRIPTIONS[rel],
            )
            if patch:
                base_patches[rel] = patch
        changed_base = {rel for rel in snapshot_cpu if snapshot_cpu[rel] != snapshot_base[rel]}
        unnamed_base = changed_base - set(BASE_PATCH_NAMES)
        if unnamed_base:
            raise SystemExit(
                "base substitutions changed files without patch names: "
                + ", ".join(sorted(unnamed_base))
            )

        cuda_patches: dict[str, bytes] = {}
        for rel in CUDA_PATCH_FILES:
            patch = generate_patch(
                rel,
                snapshot_cpu[rel],
                snapshot_cuda[rel],
                CUDA_PATCH_DESCRIPTIONS[rel],
            )
            if patch:
                cuda_patches[rel] = patch
        changed_cuda = {rel for rel in snapshot_cuda if snapshot_cuda[rel] != snapshot_cpu[rel]}
        unnamed_cuda = changed_cuda - set(CUDA_PATCH_NAMES)
        if unnamed_cuda:
            raise SystemExit(
                "CUDA substitutions changed files without patch names: "
                + ", ".join(sorted(unnamed_cuda))
            )

        print(
            f"generated {len(base_patches)} base and {len(cuda_patches)} CUDA patch file(s)"
        )

        # Verification: apply the generated patches to a clean tree in build
        # order (alphabetical file-name glob per directory) and require
        # byte-exact equality with the substitution result.
        materialize(verify)
        apply_patch_file(verify, safe_training_patch)
        normalize_patch_inputs(verify)

        for rel in BASE_PATCH_FILES:
            if rel in base_patches:
                patch_path = temp_patches / BASE_PATCH_NAMES[rel]
                patch_path.write_bytes(base_patches[rel])
                apply_patch_file(verify, patch_path)
        problems = compare_trees(snapshot_cpu, verify)
        if problems:
            raise SystemExit(
                "base patch verification failed:\n" + "\n".join(problems)
            )
        print("base patches apply cleanly and reproduce the CPU tree byte-for-byte")

        for rel in CUDA_PATCH_FILES:
            if rel in cuda_patches:
                patch_path = temp_patches / CUDA_PATCH_NAMES[rel]
                patch_path.write_bytes(cuda_patches[rel])
                apply_patch_file(verify, patch_path)
        problems = compare_trees(snapshot_cuda, verify)
        if problems:
            raise SystemExit(
                "CUDA patch verification failed:\n" + "\n".join(problems)
            )
        print("CUDA patches apply cleanly and reproduce the CUDA tree byte-for-byte")

        # Re-run the project's own assertions against the patched trees.
        failures = run_grep_checks(
            snapshot_cpu, BASE_GREPS, "cpu"
        ) + run_grep_checks(snapshot_cuda, BASE_GREPS + CUDA_GREPS, "cuda")
        if failures:
            raise SystemExit(
                "installCheck grep assertions failed:\n" + "\n".join(failures)
            )
        print("installCheck grep assertions: OK")

        run_project_tests(repo_root, work)
        print("AST policy and training subprocess security tests: OK")

        for label, counts in (("base", base_counts), ("cuda", cuda_counts)):
            print(f"\n{label} substitution match counts:")
            for rel, description, count in counts:
                print(f"  {count}x  {rel}: {description}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
        shutil.rmtree(temp_patches, ignore_errors=True)

    if args.verify:
        drift = compare_patch_dirs(repo_root, base_patches, cuda_patches)
        if drift:
            raise SystemExit("patches out of sync:\n  " + "\n  ".join(drift))
        print("in-tree patch files match the regenerated set byte-for-byte")
        return

    if args.dry_run:
        print("\ndry run: patch files not written")
        return

    for target, patches, names in (
        (repo_root / "nix/patches/rvc", base_patches, BASE_PATCH_NAMES),
        (repo_root / "nix/patches/cuda", cuda_patches, CUDA_PATCH_NAMES),
    ):
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True)
        for rel, content in patches.items():
            (target / names[rel]).write_bytes(content)
        print(f"wrote {len(patches)} patch file(s) to {target}")


def compare_patch_dirs(
    repo_root: Path,
    base_patches: dict[str, bytes],
    cuda_patches: dict[str, bytes],
) -> list[str]:
    problems: list[str] = []
    for target, patches, names in (
        (repo_root / "nix/patches/rvc", base_patches, BASE_PATCH_NAMES),
        (repo_root / "nix/patches/cuda", cuda_patches, CUDA_PATCH_NAMES),
    ):
        expected_files = {names[rel] for rel in patches}
        existing = {p.name for p in target.glob("*.patch")} if target.exists() else set()
        for missing in sorted(expected_files - existing):
            problems.append(f"{target.name}: missing {missing}")
        for extra in sorted(existing - expected_files):
            problems.append(f"{target.name}: unexpected {extra}")
        for rel, content in patches.items():
            path = target / names[rel]
            if path.exists() and path.read_bytes() != content:
                problems.append(
                    f"{target.name}: {names[rel]} differs from the regenerated content"
                )
    return problems


if __name__ == "__main__":
    main()
