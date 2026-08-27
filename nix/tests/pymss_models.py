#!/usr/bin/env python3
"""Validate packaged PyMSS catalog paths and YAML configurations."""

import sys
from pathlib import Path

from pymss import resolve_model
from pymss_core.config import load_config


def validate_model(name: str) -> None:
    resolved = resolve_model(name)
    model_path = Path(resolved["model_path"])
    config_path = Path(resolved["config_path"])
    if not model_path.is_file():
        raise SystemExit(f"{name}: model path is not a file: {model_path}")
    if not config_path.is_file():
        raise SystemExit(f"{name}: config path is not a file: {config_path}")

    config = load_config(config_path)
    if config.audio.sample_rate <= 0:
        raise SystemExit(f"{name}: invalid sample rate in {config_path}")
    if not config.model:
        raise SystemExit(f"{name}: missing model configuration in {config_path}")


def main(argv: list[str]) -> None:
    model_names = argv[1:]
    if not model_names:
        raise SystemExit(f"usage: {argv[0]} MODEL_NAME [MODEL_NAME ...]")

    for name in model_names:
        validate_model(name)

    print(f"PyMSS packaged model catalog and configs: OK ({len(model_names)} models)")


if __name__ == "__main__":
    main(sys.argv)
