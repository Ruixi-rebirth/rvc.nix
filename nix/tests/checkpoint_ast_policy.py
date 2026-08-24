"""Reject unclassified weights_only=False checkpoint loads.

PyTorch 2.6 and newer uses weights-only loading by default. The package pins
2.7.1 and the runtime security test enforces the minimum version, so ordinary
upstream ``torch.load`` calls do not need downstream edits. This AST check only
locks down the small set of legacy PyMSS formats that still require pickle.
"""

import ast
import sys
from collections import Counter
from pathlib import Path


source_root = Path(sys.argv[1])

# Only security exceptions are count-locked. Ordinary load sites may change
# upstream without forcing a downstream patch as long as they do not request
# unrestricted pickle explicitly.
allowed_false = {
    ("tools/pymss_core/checkpoint.py", "load_checkpoint"): 2,
    ("tools/pymss/separator.py", "_load_state_dict"): 2,
    ("tools/pymss_core/modules/legacy_demucs.py", "_load_raw_checkpoint"): 1,
}
found_false = Counter()
all_loads = 0


def torch_load_names(tree: ast.Module) -> tuple[set[str], set[str]]:
    module_names = {"torch"}
    load_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "torch":
                    module_names.add(alias.asname or "torch")
        elif isinstance(node, ast.ImportFrom) and node.module == "torch":
            for alias in node.names:
                if alias.name == "load":
                    load_names.add(alias.asname or "load")
    return module_names, load_names


def is_torch_load(node: ast.Call, module_names: set[str], load_names: set[str]) -> bool:
    if isinstance(node.func, ast.Name):
        return node.func.id in load_names
    return (
        isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id in module_names
        and node.func.attr == "load"
    )


class LoadVisitor(ast.NodeVisitor):
    def __init__(self, relative: str, module_names: set[str], load_names: set[str]):
        self.relative = relative
        self.module_names = module_names
        self.load_names = load_names
        self.function_names: list[str] = []

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self.function_names.append(node.name)
        self.generic_visit(node)
        self.function_names.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    def visit_Call(self, node: ast.Call) -> None:
        global all_loads
        if is_torch_load(node, self.module_names, self.load_names):
            all_loads += 1

        weights_only = next(
            (keyword.value for keyword in node.keywords if keyword.arg == "weights_only"),
            None,
        )
        if isinstance(weights_only, ast.Constant) and weights_only.value is False:
            function_name = self.function_names[-1] if self.function_names else "<module>"
            key = (self.relative, function_name)
            if key not in allowed_false:
                raise AssertionError(
                    f"unclassified weights_only=False at {self.relative}:{node.lineno}"
                )
            found_false[key] += 1
        self.generic_visit(node)


for source_path in source_root.rglob("*.py"):
    relative = source_path.relative_to(source_root).as_posix()
    tree = ast.parse(source_path.read_text(encoding="utf-8"), filename=str(source_path))
    module_names, load_names = torch_load_names(tree)
    LoadVisitor(relative, module_names, load_names).visit(tree)

assert dict(found_false) == allowed_false, (dict(found_false), allowed_false)
print(
    "RVC checkpoint AST policy: OK "
    f"({all_loads} torch.load calls, {sum(found_false.values())} classified legacy loads)"
)
