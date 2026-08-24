"""Patch rule data for generate_patches.py.

This file is the source of truth for every generated change to upstream RVC:
patch order, patch-level explanations, substitutions, and verification
assertions. Edit it when a downstream change is added or removed, then run the
generator and review the resulting patches.
"""


# The declaration order is the patch application order. The generator assigns
# the numeric prefix, so adding or removing a patch never requires hand-editing
# a second name table.
BASE_PATCH_FILES = (
    "realtime_gui.py",
    "webui.py",
    "infer/cli.py",
    "infer/hubert.py",
    "tools/pymss_core/checkpoint.py",
    "tools/pymss/modules/vocal_remover/vr_separator.py",
    "train/process_ckpt.py",
)

CUDA_PATCH_FILES = ("configs/config.py",)


# These explanations are emitted automatically at the top of each patch.
BASE_PATCH_DESCRIPTIONS = {
    "realtime_gui.py": (
        "Keep realtime data and configuration writable, fix model selectors, "
        "handle unavailable audio devices, and support headless smoke tests."
    ),
    "webui.py": (
        "Bind the WebUI to a configurable loopback default and support "
        "headless smoke tests."
    ),
    "infer/cli.py": "Resolve CLI assets from the mutable RVC data directory.",
    "infer/hubert.py": (
        "Resolve the packaged HuBERT model from the mutable RVC data directory."
    ),
    "tools/pymss_core/checkpoint.py": (
        "Reject unrestricted generic PyMSS loads while preserving explicitly "
        "classified legacy formats."
    ),
    "tools/pymss/modules/vocal_remover/vr_separator.py": (
        "Remove the unrestricted-pickle fallback from VR model loading."
    ),
    "train/process_ckpt.py": (
        "Constrain generated model outputs to the weights directory."
    ),
}

CUDA_PATCH_DESCRIPTIONS = {
    "configs/config.py": (
        "Make the CUDA package fail closed when no supported NVIDIA device is "
        "usable."
    ),
}


BASE_RULES = [
    # realtime_gui.py: writable state, corrected file pickers, smoke-test hook
    (
        "realtime_gui.py",
        """now_dir = os.path.dirname(os.path.abspath(__file__))""",
        """now_dir = os.environ.get("RVC_DATA_DIR", os.path.dirname(os.path.abspath(__file__)))""",
        "route the realtime GUI data root through RVC_DATA_DIR",
    ),
    (
        "realtime_gui.py",
        """realtime_config_path = os.path.join(now_dir, "configs", "config.json")""",
        """config_dir = os.environ.get("RVC_CONFIG_DIR", os.path.join(now_dir, "configs"))
os.makedirs(config_dir, exist_ok=True)
realtime_config_path = os.path.join(config_dir, "realtime.json")""",
        "route the realtime GUI config through RVC_CONFIG_DIR",
    ),
    (
        "realtime_gui.py",
        """    gui = GUI()""",
        """    if os.environ.get("RVC_SMOKE_TEST") == "1":
        print("RVC realtime smoke test: OK", flush=True)
    else:
        gui = GUI()""",
        "exit before opening a window during the headless smoke test",
    ),
    (
        "realtime_gui.py",
        """file_types=((". pth"),),""",
        """file_types=(("RVC model", "*.pth"),),""",
        "fix the model file dialog glob",
    ),
    (
        "realtime_gui.py",
        """file_types=((". index"),),""",
        """file_types=(("RVC index", "*.index"),),""",
        "fix the index file dialog glob",
    ),
    (
        "realtime_gui.py",
        '''                    if (
                        self.gui_config.sg_input_device not in self.input_devices
                        and len(self.input_devices) > 0
                    ):
                        self.gui_config.sg_input_device = self.input_devices[0]
                    self.window["sg_input_device"].Update(values=self.input_devices)
                    self.window["sg_input_device"].Update(
                        value=self.gui_config.sg_input_device
                    )
                    if self.gui_config.sg_output_device not in self.output_devices:
                        self.gui_config.sg_output_device = self.output_devices[0]''',
        '''                    if self.gui_config.sg_input_device not in self.input_devices:
                        self.gui_config.sg_input_device = ""
                    self.window["sg_input_device"].Update(values=self.input_devices)
                    self.window["sg_input_device"].Update(
                        value=self.gui_config.sg_input_device
                    )
                    if self.gui_config.sg_output_device not in self.output_devices:
                        self.gui_config.sg_output_device = ""''',
        "leave unavailable host APIs empty instead of selecting another device",
    ),
    (
        "realtime_gui.py",
        '''        def set_values(self, values):
            if len(values["pth_path"].strip()) == 0:''',
        '''        def set_values(self, values):
            if (
                values["sg_input_device"] not in self.input_devices
                or values["sg_output_device"] not in self.output_devices
            ):
                sg.popup_error(
                    "%s / %s" % (i18n("输入设备"), i18n("输出设备")),
                    title=i18n("音频设备"),
                )
                return False
            if len(values["pth_path"].strip()) == 0:''',
        "reject missing or stale audio-device selections before loading a model",
    ),
    (
        "realtime_gui.py",
        '''                        printt(i18n("CUDA可用：%s"), torch.cuda.is_available())
                        self.start_vc()
                        settings = {''',
        '''                        printt(i18n("CUDA可用：%s"), torch.cuda.is_available())
                        try:
                            self.start_vc()
                        except sd.PortAudioError as error:
                            self.stop_stream()
                            printt("%s: %s", i18n("音频设备"), error)
                            sg.popup_error(str(error), title=i18n("音频设备"))
                            continue
                        settings = {''',
        "keep the GUI open when PortAudio cannot open the selected devices",
    ),
    # webui.py: safe bind default and smoke-test hook
    (
        "webui.py",
        """    if config.iscolab:""",
        """    if os.environ.get("RVC_SMOKE_TEST") == "1":
        print("RVC WebUI smoke test: OK", flush=True)
    elif config.iscolab:""",
        "exit before launching Gradio during the headless smoke test",
    ),
    (
        "webui.py",
        """now_dir = os.getcwd()""",
        """now_dir = os.getcwd()
WEBUI_HOST = os.environ.get("RVC_WEBUI_HOST", "127.0.0.1")""",
        "bind the WebUI to 127.0.0.1 unless RVC_WEBUI_HOST overrides it",
    ),
    (
        "webui.py",
        """def find_available_port(start_port, host="0.0.0.0"):""",
        """def find_available_port(start_port, host=WEBUI_HOST):""",
        "probe the configured WebUI host when selecting an available port",
    ),
    (
        "webui.py",
        """server_name="0.0.0.0",""",
        """server_name=WEBUI_HOST,""",
        "launch Gradio on the configured WebUI host",
    ),
    # infer/cli.py and infer/hubert.py: mutable packaged asset roots
    (
        "infer/cli.py",
        """PROJECT_ROOT = Path(__file__).resolve().parent.parent""",
        """SOURCE_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = Path(os.environ.get("RVC_DATA_DIR", SOURCE_ROOT)).expanduser().resolve()""",
        "route CLI assets through RVC_DATA_DIR",
    ),
    (
        "infer/hubert.py",
        """import logging""",
        """import logging
import os""",
        "import os for the RVC_DATA_DIR override",
    ),
    (
        "infer/hubert.py",
        """PROJECT_ROOT = Path(__file__).resolve().parent.parent""",
        """SOURCE_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = Path(os.environ.get("RVC_DATA_DIR", SOURCE_ROOT)).expanduser().resolve()""",
        "route the HuBERT model root through RVC_DATA_DIR",
    ),
    # train/process_ckpt.py: model outputs stay in the configured weights root
    (
        "train/process_ckpt.py",
        """import json""",
        """import json
import re
from pathlib import Path""",
        "import the path validation helpers",
    ),
    (
        "train/process_ckpt.py",
        """i18n = I18nAuto()


def normalize_speaker_info""",
        """i18n = I18nAuto()
WEIGHT_ROOT = Path(os.environ.get("weight_root", "assets/weights")).expanduser().resolve()


def model_output_path(filename):
    filename = str(filename or "").strip()
    if filename in {"", ".", ".."} or re.fullmatch(r"[A-Za-z0-9._-]{1,132}", filename) is None:
        raise ValueError(i18n("模型名称只能包含字母、数字、点、下划线和连字符"))
    output = (WEIGHT_ROOT / filename).resolve()
    if not output.is_relative_to(WEIGHT_ROOT):
        raise ValueError(i18n("模型输出路径必须位于weights目录"))
    WEIGHT_ROOT.mkdir(parents=True, exist_ok=True)
    return output


def normalize_speaker_info""",
        "validate model output names and keep them inside weight_root",
    ),
    (
        "train/process_ckpt.py",
        """torch.save(opt, "assets/weights/%s.pth" % name)""",
        """torch.save(opt, model_output_path("%s.pth" % name))""",
        "write converted checkpoints through the validated output path",
    ),
    (
        "train/process_ckpt.py",
        """torch.save(ckpt, "assets/weights/%s" % name)""",
        """torch.save(ckpt, model_output_path(name))""",
        "write extracted checkpoints through the validated output path",
    ),
    # PyMSS: PyTorch >= 2.6 is safe by default; only block unsafe overrides
    # and preserve the formats that upstream explicitly classifies as legacy.
    (
        "tools/pymss_core/checkpoint.py",
        """    except TypeError:
        kwargs.pop("mmap", None)
        try:
            return torch.load(path, **kwargs)
        except TypeError:
            kwargs.pop("weights_only", None)
            return torch.load(path, **kwargs)""",
        """    except TypeError:
        kwargs.pop("mmap", None)
        return torch.load(path, **kwargs)""",
        "remove the fallback that silently discards an explicit load policy",
    ),
    (
        "tools/pymss_core/checkpoint.py",
        """    if model_type == "apollo":
        weights_only = False if weights_only is None else weights_only
    return _torch_load(path, map_location=map_location, weights_only=weights_only, mmap=mmap)""",
        """    if model_type == "apollo":
        return _torch_load(
            path, map_location=map_location, weights_only=False, mmap=mmap
        )
    if weights_only is False:
        raise ValueError(
            "weights_only=False is restricted to explicitly classified legacy model types"
        )
    return _torch_load(path, map_location=map_location, weights_only=weights_only, mmap=mmap)""",
        "reject weights_only=False for ordinary PyMSS checkpoints",
    ),
    (
        "tools/pymss/modules/vocal_remover/vr_separator.py",
        """        try:
            state_dict = torch.load(self.model_path, map_location="cpu", weights_only=True)
        except TypeError:
            state_dict = torch.load(self.model_path, map_location="cpu")
        except Exception:
            state_dict = torch.load(self.model_path, map_location="cpu", weights_only=False)""",
        """        state_dict = torch.load(
            self.model_path, map_location="cpu", weights_only=True
        )""",
        "remove the unrestricted VR checkpoint fallback",
    ),
]


CUDA_RULES = [
    (
        "configs/config.py",
        """CUDA_AVAILABLE = torch.cuda.is_available()""",
        """CUDA_AVAILABLE = torch.cuda.is_available()
if os.environ.get("RVC_REQUIRE_CUDA") == "1" and not CUDA_AVAILABLE:
    raise RuntimeError("The CUDA RVC package requires a usable NVIDIA device; check the host driver and RVC_DRIVER_LIBRARY_PATH")""",
        "fail closed when the CUDA package has no usable device",
    ),
    (
        "configs/config.py",
        """IS_GPU = bool(GPU_INFOS)""",
        """IS_GPU = bool(GPU_INFOS)
if os.environ.get("RVC_REQUIRE_CUDA") == "1" and not IS_GPU:
    raise RuntimeError("No visible NVIDIA GPU satisfies the RVC minimum of 4 GiB memory and compute capability 5.3")""",
        "fail closed when no GPU meets RVC's minimum requirements",
    ),
]


# Generator-time assertions mirror the package's required source contracts.
BASE_GREPS = [
    ("realtime_gui.py", "RVC_DATA_DIR", True),
    ("realtime_gui.py", "RVC_CONFIG_DIR", True),
    ("realtime_gui.py", "RVC realtime smoke test: OK", True),
    ("realtime_gui.py", 'file_types=(("RVC model", "*.pth"),)', True),
    ("realtime_gui.py", 'file_types=(("RVC index", "*.index"),)', True),
    ("realtime_gui.py", 'self.gui_config.sg_input_device = ""', True),
    ("realtime_gui.py", 'self.gui_config.sg_output_device = ""', True),
    ("realtime_gui.py", 'values["sg_input_device"] not in self.input_devices', True),
    ("realtime_gui.py", "except sd.PortAudioError as error:", True),
    ("realtime_gui.py", '"sr_type": "sr_model"', True),
    ("realtime_gui.py", '"sr_type": "sr_device"', False),
    ("realtime_gui.py", "RVC_HIDDEN_INPUT_DEVICES", False),
    ("realtime_gui.py", "RVC_HIDDEN_OUTPUT_DEVICES", False),
    ("realtime_gui.py", "RVC_DEFAULT_INPUT_NAME", False),
    ("webui.py", "RVC WebUI smoke test: OK", True),
    ("webui.py", "RVC_WEBUI_HOST", True),
    ("webui.py", "RVC_TEMP_DIR", False),
    ("webui.py", "safe_experiment_name", False),
    ("webui.py", "validated_gpu_devices", True),
    ("webui.py", 'kwargs = {"shell": False', True),
    ("webui.py", "ast.literal_eval(", True),
    ("webui.py", '"shell": True', False),
    ("infer/cli.py", "RVC_DATA_DIR", True),
    ("infer/hubert.py", "RVC_DATA_DIR", True),
    ("train/process_ckpt.py", "model_output_path", True),
    (
        "tools/pymss_core/checkpoint.py",
        "weights_only=False is restricted to explicitly classified legacy model types",
        True,
    ),
]

CUDA_GREPS = [
    ("configs/config.py", "RVC_REQUIRE_CUDA", True),
    (
        "configs/config.py",
        "No visible NVIDIA GPU satisfies the RVC minimum",
        True,
    ),
]
