"""Run real HuBERT and RMVPE forwards with the packaged inference models.

Exercises the built Python environment plus the pinned model assets on the
requested device (cpu/cuda) during the package installCheckPhase.
"""

import gc
import os
import sys
from pathlib import Path

import numpy as np
import torch


def main() -> None:
    expected_device = sys.argv[1]
    if expected_device not in {"cpu", "cuda"}:
        raise SystemExit("expected device must be cpu or cuda")

    data_root = Path(os.environ["RVC_DATA_DIR"])

    from configs.config import infer_device, infer_dtype

    if infer_device.type != expected_device:
        raise RuntimeError(f"RVC selected {infer_device}, expected {expected_device}")
    if expected_device == "cpu" and infer_dtype != torch.float32:
        raise RuntimeError(f"CPU inference selected unexpected dtype {infer_dtype}")

    from infer.hubert import extract_hubert_features, load_hubert_model

    hubert = load_hubert_model(
        str(infer_device),
        infer_dtype == torch.float16,
    )
    hubert_parameter = next(hubert.parameters())
    if hubert_parameter.device.type != expected_device:
        raise RuntimeError(f"HuBERT loaded on {hubert_parameter.device}")
    if hubert_parameter.dtype != infer_dtype:
        raise RuntimeError(f"HuBERT loaded as {hubert_parameter.dtype}")

    audio_tensor = torch.zeros(
        (1, 16000),
        device=infer_device,
        dtype=infer_dtype,
    )
    with torch.inference_mode():
        features_v1 = extract_hubert_features(hubert, audio_tensor, "v1")
        features_v2 = extract_hubert_features(hubert, audio_tensor, "v2")

    if features_v1.device.type != expected_device:
        raise RuntimeError(f"HuBERT v1 output is on {features_v1.device}")
    if features_v2.device.type != expected_device:
        raise RuntimeError(f"HuBERT v2 output is on {features_v2.device}")
    if features_v1.shape[-1] != 256:
        raise RuntimeError(f"unexpected HuBERT v1 shape {features_v1.shape}")
    if features_v2.shape[-1] != 768:
        raise RuntimeError(f"unexpected HuBERT v2 shape {features_v2.shape}")
    if not torch.isfinite(features_v1).all().item():
        raise RuntimeError("HuBERT v1 produced non-finite values")
    if not torch.isfinite(features_v2).all().item():
        raise RuntimeError("HuBERT v2 produced non-finite values")

    print(
        "HuBERT model forward: OK",
        tuple(features_v1.shape),
        tuple(features_v2.shape),
        features_v2.device,
        features_v2.dtype,
    )

    del features_v1, features_v2, audio_tensor, hubert, hubert_parameter
    gc.collect()
    if expected_device == "cuda":
        torch.cuda.empty_cache()

    from infer.rmvpe import RMVPE

    rmvpe = RMVPE(
        str(data_root / "assets/rmvpe/rmvpe.pt"),
        infer_dtype == torch.float16,
        str(infer_device),
    )
    rmvpe_parameter = next(rmvpe.model.parameters())
    if rmvpe_parameter.device.type != expected_device:
        raise RuntimeError(f"RMVPE loaded on {rmvpe_parameter.device}")

    samples = np.sin(
        2 * np.pi * 220 * np.arange(16000, dtype=np.float32) / 16000
    ).astype(np.float32)
    mel = rmvpe.extract_mel(samples)
    if mel.device.type != expected_device:
        raise RuntimeError(f"RMVPE mel tensor is on {mel.device}")
    with torch.inference_mode():
        hidden = rmvpe.mel2hidden(mel)
        f0 = rmvpe.infer_from_audio(samples)
    if hidden.device.type != expected_device:
        raise RuntimeError(f"RMVPE hidden tensor is on {hidden.device}")
    if not torch.isfinite(hidden).all().item():
        raise RuntimeError("RMVPE produced non-finite hidden values")

    if f0.size == 0 or not np.isfinite(f0).all():
        raise RuntimeError("RMVPE produced an invalid F0 contour")

    print(
        "RMVPE model forward: OK",
        tuple(hidden.shape),
        hidden.device,
        hidden.dtype,
        f0.shape,
    )


if __name__ == "__main__":
    main()
