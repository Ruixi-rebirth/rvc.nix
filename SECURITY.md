# Security

## Supported versions

Only the exact upstream RVC revision recorded in `flake.lock` is supported.
Upstream updates are deliberate pull requests, never an automatic moving
target, and every patch applied on top of upstream is reviewed when that
revision changes.

## Scope

In scope: the Nix packaging (`nix/package.nix`, `nix/python-overrides.nix`,
`flake.nix`), the launchers, the PipeWire NixOS module (`nix/module.nix`),
the patches under `nix/patches/`, and the pinned model metadata
(`nix/models.nix`).

Out of scope: the upstream RVC codebase itself (report those to
[RVC-Project](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)),
user-provided model files, and host configuration.

## Security model

The packaging hardens the single-user, local-machine threat model:

- **Checkpoints.** PyTorch is pinned to 2.7.1, where omitted `weights_only`
  defaults to safe weights-only loading. Explicit unrestricted pickle is
  rejected except for classified legacy Demucs/TasNet, HTDemucs, and Apollo
  formats. The build rejects Torch versions below the CVE-2025-32434 fix
  (2.6.0), while an AST policy and malicious-pickle runtime test enforce the
  exception boundary (`nix/tests/checkpoint_ast_policy.py`,
  `nix/tests/checkpoint_runtime_security.py`).
- **Training subprocesses.** WebUI training commands are argv lists executed
  with `shell=False`, GPU fields are validated against a whitelist, and the
  training log parser uses `ast.literal_eval` instead of `eval`
  (`nix/patches/safe-training-subprocesses.patch`).
- **Model outputs.** Generated checkpoint names are validated and constrained
  to the configured weights directory.
- **Network exposure.** The WebUI binds `127.0.0.1` by default. It is a
  trusted single-user interface with filesystem and training controls, and
  the pinned Gradio 3.x has known CVEs that are only mitigated by the
  localhost binding; authentication at a reverse proxy does not make it safe
  for untrusted users. Treat `RVC_WEBUI_HOST` as a last resort.
- **Runtime isolation.** Source and model assets are read-only in the Nix
  store; user models, logs, and configuration live under XDG paths. Hugging
  Face, Gradio, and ONNX Runtime telemetry default to disabled while explicit
  user environment settings are respected. Runtime network access is not
  forcibly disabled because upstream PyMSS exposes model download commands.
- **CUDA fail-closed.** The CUDA variant requires a usable NVIDIA device that
  meets RVC's minimum at startup instead of silently selecting CPU. Real model
  forwards cover HuBERT, RMVPE, offline CLI, and realtime synthesis behavior.

## Reporting a vulnerability

Use GitHub's private Security Advisory workflow (**Security → Report a
vulnerability**) rather than a public issue. Include the affected flake
output, host details, and a minimal reproduction. There is no bug bounty;
reports are triaged as maintainer time allows. Please give a reasonable
window before public disclosure.
