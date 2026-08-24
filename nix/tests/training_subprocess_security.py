"""Training subprocess policy: argv lists, shell=False, validated GPU fields.

Run by the package installCheckPhase against the patched webui.py; proves the
only Popen call site cannot be reached with a shell command string.
"""

import ast
import os
import re
import sys


source_path = sys.argv[1]
source = open(source_path, encoding="utf-8").read()
tree = ast.parse(source, filename=source_path)
functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}

# Every training-stage command is built as an argv list. The sole Popen
# call lives in the wrapper tested below with a fake process launcher.
for name in {
    "run_preprocess_dataset",
    "run_extract_f0_feature",
    "run_train_model",
    "run_train_index",
}:
    assignments = [
        node
        for node in ast.walk(functions[name])
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == "cmd"
            for target in node.targets
        )
    ]
    assert assignments
    assert all(isinstance(node.value, ast.List) for node in assignments)
popen_calls = [
    node
    for node in ast.walk(tree)
    if isinstance(node, ast.Call)
    and isinstance(node.func, ast.Name)
    and node.func.id == "Popen"
]
assert len(popen_calls) == 1

change_info_calls = [
    node.func
    for node in ast.walk(functions["change_info_"])
    if isinstance(node, ast.Call)
]
assert any(
    isinstance(function, ast.Attribute)
    and isinstance(function.value, ast.Name)
    and function.value.id == "ast"
    and function.attr == "literal_eval"
    for function in change_info_calls
)
assert not any(
    isinstance(function, ast.Name) and function.id == "eval"
    for function in change_info_calls
)
try:
    ast.literal_eval("__import__('os').system('touch /tmp/rvc-eval-pwn')")
except (ValueError, SyntaxError):
    pass
else:
    raise AssertionError("malicious train.log expression was accepted")

selected = ast.Module(
    body=[
        functions["validated_gpu_devices"],
        functions["start_train_process"],
    ],
    type_ignores=[],
)


class Lock:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class Logger:
    def info(self, *_args):
        pass


class Platform:
    @staticmethod
    def system():
        return "Linux"


class Process:
    returncode = None

    def poll(self):
        return None


captured = []


def fake_popen(argv, **kwargs):
    captured.append((argv, kwargs))
    return Process()


namespace = {
    "re": re,
    "os": os,
    "platform": Platform,
    "subprocess": __import__("subprocess"),
    "Popen": fake_popen,
    "GPU_INDEX": {0, 2},
    "i18n": lambda message: message,
    "logger": Logger(),
    "TRAIN_TASK_LOCK": Lock(),
    "now_dir": "/tmp/RVC test cwd",
}
exec(compile(selected, source_path, "exec"), namespace)

validate = namespace["validated_gpu_devices"]
assert validate("0-2", "GPU") == ["0", "2"]
assert validate("0-0", "GPU") == ["0", "0"]
for malicious in ("0;touch /tmp/pwn", "0-$(id)", "0 -2", "../0", "3"):
    try:
        validate(malicious, "GPU")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid GPU list accepted: %r" % malicious)
try:
    validate("0-0", "GPU", allow_duplicates=False)
except ValueError:
    pass
else:
    raise AssertionError("duplicate training GPU accepted")

state = {"processes": [], "stop_requested": False, "name": "test"}
argument = "/tmp/带 空格;$(touch should-not-run)"
namespace["start_train_process"](
    state,
    ["/nix/store/python with space", "train/preprocess.py", argument],
)
argv, kwargs = captured[-1]
assert argv[2] == argument
assert kwargs["shell"] is False
assert kwargs["start_new_session"] is True
assert "env" not in kwargs

namespace["start_train_process"](
    state,
    ["/nix/store/python", "train/train.py", "-pg", argument],
)
argv, kwargs = captured[-1]
assert argv[-1] == argument
assert kwargs["shell"] is False
assert kwargs["env"]["RVC_CUDA_GRAPH"] == "0"
try:
    namespace["start_train_process"](state, "python train/train.py; touch /tmp/pwn")
except TypeError:
    pass
else:
    raise AssertionError("string command accepted")
print("RVC training subprocess security tests: OK")
