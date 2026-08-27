"""Run one realtime synthesizer forward (net_g through rtrvc.infer).

Used by the package installCheckPhase and the live acceptance script on the
requested device (cpu/cuda).
"""

import os
import sys
from pathlib import Path

import numpy as np
import torch


def main() -> None:
    checkpoint = Path(sys.argv[1])
    expected_device = sys.argv[2]
    if expected_device not in {"cpu", "cuda"}:
        raise SystemExit("expected device must be cpu or cuda")

    if len(sys.argv) == 4:
        if sys.argv[3] != "extract-v2-40k":
            raise SystemExit("unknown checkpoint preparation mode")
        extracted_dir = Path(os.environ["RVC_CACHE_DIR"]) / "realtime-weights"
        extracted_dir.mkdir(parents=True, exist_ok=True)
        os.environ["weight_root"] = str(extracted_dir)
        from train.process_ckpt import extract_small_model

        result = extract_small_model(
            str(checkpoint),
            "install-check",
            "40k",
            1,
            "install check",
            "v2",
        )
        checkpoint = extracted_dir / "install-check.pth"
        if not checkpoint.is_file():
            raise RuntimeError(f"failed to extract inference checkpoint: {result}")
    elif len(sys.argv) != 3:
        raise SystemExit(
            "usage: realtime_infer_forward.py CHECKPOINT DEVICE "
            "[extract-v2-40k]"
        )

    from configs.config import infer_device, infer_dtype

    if infer_device.type != expected_device:
        raise RuntimeError(f"RVC selected {infer_device}, expected {expected_device}")

    class _Config:
        device = str(infer_device)
        is_half = infer_dtype == torch.float16

    from infer.rtrvc import RVC

    rvc = RVC(
        0,
        0.0,
        str(checkpoint),
        "",
        0.0,
        _Config(),
        None,
    )
    if rvc.net_g is None:
        raise RuntimeError("realtime synthesizer failed to load")

    device = torch.device(infer_device)
    sample_count = 160 * 281  # 44_960 samples at 16 kHz
    phase = torch.arange(sample_count, device=device, dtype=torch.float32) / 16000.0
    input_wav = 0.3 * torch.sin(2 * np.pi * 220.0 * phase)

    output = rvc.infer(input_wav, 4000, 250, 31, "rmvpe")
    if not torch.is_tensor(output) or output.device.type != expected_device:
        raise RuntimeError(
            f"realtime synthesis produced "
            f"{getattr(output, 'device', type(output).__name__)}"
        )
    if output.numel() == 0 or not torch.isfinite(output).all().item():
        raise RuntimeError("realtime synthesis output is empty or non-finite")

    print(
        "RVC realtime inference forward: OK",
        tuple(output.shape),
        output.device,
        output.dtype,
    )


if __name__ == "__main__":
    main()
