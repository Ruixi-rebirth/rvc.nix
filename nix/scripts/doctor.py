"""Runtime diagnostics for the packaged RVC environment.

Reports the Torch build, CUDA state, core extension imports, an ONNX session,
and (for the CUDA variant) a cuDNN loader check. Exits unsuccessfully when the
selected acceleration cannot actually be used.
"""

import ctypes
import importlib
import sys
import warnings
from pathlib import Path

import numpy as np
import torch


def main() -> None:
    acceleration = sys.argv[1]
    cuda_available = torch.cuda.is_available()

    print(f"torch: {torch.__version__}")
    print(f"CUDA runtime: {torch.version.cuda}")
    print(f"CUDA available: {cuda_available}")
    if cuda_available:
        try:
            device_name = torch.cuda.get_device_name()
        except Exception as exc:
            device_name = f"unavailable ({exc})"
    else:
        device_name = "CPU"
    print("device:", device_name)

    is_cuda = acceleration.startswith("cuda")

    if is_cuda and not cuda_available:
        raise SystemExit(
            "CUDA package selected, but PyTorch cannot use an NVIDIA device. "
            "Check the host driver and RVC_DRIVER_LIBRARY_PATH."
        )

    warnings.filterwarnings(
        "ignore",
        message=r"pkg_resources is deprecated as an API.*",
        category=UserWarning,
    )
    modules = (
        "av",
        "cv2",
        "faiss",
        "gradio",
        "librosa",
        "sounddevice",
        "soundfile",
    )
    if acceleration == "cpu":
        modules += ("torchvision",)
    for module in modules:
        importlib.import_module(module)
    print("core imports: OK")

    import onnxruntime as ort
    from onnxruntime.datasets import get_example

    session = ort.InferenceSession(
        get_example("mul_1.onnx"),
        providers=["CPUExecutionProvider"],
    )
    values = np.arange(6, dtype=np.float32).reshape(3, 2)
    expected = np.array([[0, 2], [6, 12], [20, 30]], dtype=np.float32)
    np.testing.assert_allclose(session.run(None, {"X": values})[0], expected)
    print("ONNX Runtime CPU provider: OK", ort.__version__)

    if is_cuda:
        # is_available() alone can report True even when the first real
        # launch fails (stale drivers or "no kernel image" errors), so
        # execute a tiny kernel instead of trusting the runtime probe.
        try:
            torch.zeros(8, device="cuda").sum().item()
        except Exception as exc:
            raise SystemExit(
                f"CUDA kernel launch failed; check the host driver: {exc}"
            ) from exc
        print("CUDA kernel launch: OK")

        from configs.config import infer_device

        if infer_device.type != "cuda":
            raise RuntimeError(
                f"RVC selected {infer_device} instead of a CUDA inference device"
            )
        print("RVC inference device: OK", infer_device)

        import nvidia.cudnn

        cudnn_path = Path(next(iter(nvidia.cudnn.__path__))) / "lib/libcudnn.so.9"
        cudnn = ctypes.CDLL(str(cudnn_path))
        cudnn.cudnnGetVersion.restype = ctypes.c_size_t
        version = cudnn.cudnnGetVersion()
        if version <= 0:
            raise RuntimeError(f"invalid cuDNN version: {version}")
        print("cuDNN loader: OK", version)


if __name__ == "__main__":
    main()
