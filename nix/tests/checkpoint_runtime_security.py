"""Runtime proof that malicious checkpoints cannot execute pickle payloads.

Constructs a real __reduce__ bomb, feeds it to every core RVC and PyMSS
loader, and asserts nothing executes. Run by the package installCheckPhase.
"""

import importlib.util
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import torch


# The weights_only hardening below is only trustworthy on Torch releases that
# fixed the unrestricted-pickle bypass chain (CVE-2025-32434, fixed in 2.6.0).
# Rejecting older runtimes here keeps a dependency bump from silently
# reintroducing the vulnerable loader.
_major, _minor = torch.__version__.split("+")[0].split(".")[:2]
if (int(_major), int(_minor)) < (2, 6):
    raise SystemExit(
        f"torch {torch.__version__} is vulnerable to weights_only bypasses "
        "(CVE-2025-32434); 2.6.0 or newer is required"
    )


source_root = Path(sys.argv[1])
test_root = Path(sys.argv[2])
sys.path.insert(0, str(source_root / "tools"))
sys.path.insert(0, str(source_root))
marker = test_root / "pickle-payload-executed"
malicious_checkpoint = test_root / "malicious.pth"
safe_checkpoint = test_root / "safe.pth"


class Malicious:
    def __reduce__(self):
        return os.system, (f"touch {marker}",)


torch.save(
    {
        "weight": {"emb_g.weight": torch.zeros(1, 1)},
        "payload": Malicious(),
    },
    malicious_checkpoint,
)
torch.save(
    {
        "weight": {"emb_g.weight": torch.zeros(2, 1)},
        "speaker_info": [{"id": 1, "name": "safe"}],
    },
    safe_checkpoint,
)

spec = importlib.util.spec_from_file_location(
    "rvc_cli_checkpoint_test", source_root / "infer" / "cli.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

try:
    module.load_model_metadata(malicious_checkpoint)
except Exception:
    pass
else:
    raise AssertionError("malicious checkpoint was accepted")
assert not marker.exists(), "malicious pickle payload executed"

speaker_count, speakers = module.load_model_metadata(safe_checkpoint)
assert speaker_count == 2
assert speakers == [{"id": 1, "name": "safe"}]

from pymss_core.checkpoint import load_checkpoint


try:
    load_checkpoint(malicious_checkpoint)
except Exception:
    pass
else:
    raise AssertionError("PyMSS generic loader accepted a malicious checkpoint")
assert not marker.exists(), "PyMSS generic loader executed a pickle payload"
assert load_checkpoint(safe_checkpoint)["speaker_info"][0]["name"] == "safe"
try:
    load_checkpoint(malicious_checkpoint, weights_only=False)
except ValueError:
    pass
else:
    raise AssertionError("PyMSS generic loader allowed an unrestricted override")
assert not marker.exists(), "PyMSS unrestricted override executed a pickle payload"

from pymss.modules.vocal_remover import vr_separator


class DummyModel:
    def load_state_dict(self, _state_dict):
        return None

    def eval(self):
        return self

    def to(self, *_args, **_kwargs):
        return self


vr_separator.determine_model_capacity = lambda *_args, **_kwargs: DummyModel()
separator = vr_separator.VRSeparator.__new__(vr_separator.VRSeparator)
separator.logger = SimpleNamespace(debug=lambda *_args: None)
separator.model_params = SimpleNamespace(param={"bins": 1})
separator.model_capacity = (1, 1)
separator.is_vr_51_model = False
separator.fuse_conv_bn = False
separator.mps_model_backend = "torch"
separator.torch_device = "cpu"
separator.use_channels_last = False

separator.model_path = str(malicious_checkpoint)
try:
    separator.load_model()
except Exception:
    pass
else:
    raise AssertionError("PyMSS VR loader accepted a malicious checkpoint")
assert not marker.exists(), "PyMSS VR loader executed a pickle payload"

separator.model_path = str(safe_checkpoint)
separator.load_model()
print(f"RVC/PyMSS malicious checkpoint rejection: OK (torch {torch.__version__})")
