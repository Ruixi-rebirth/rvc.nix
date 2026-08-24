{
  acceleration ? "cpu",
  inputs,
  lib,
  models ? null,
  pkgs,
}:

assert lib.assertOneOf "acceleration" acceleration [
  "cpu"
  "cuda"
];

let
  inherit (inputs)
    pyproject-build-systems
    pyproject-nix
    rvc-src
    uv2nix
    ;

  workspaceRoot = if acceleration == "cuda" then ../. else ../python/cpu;
  workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
  modelSuffix = lib.optionalString (models != null) "-with-${models.name}";
  python = pkgs.python312;

  pyprojectOverlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      pyprojectOverlay
      (
        final: _prev:
        let
          hacks = final.pkgs.callPackage pyproject-nix.build.hacks { };
        in
        {
          # Tk is supplied by nixpkgs rather than PyPI. nixpkgsPrebuilt adds
          # the dependency metadata expected by pyproject.nix's resolver.
          tkinter = hacks.nixpkgsPrebuilt {
            from = python.pkgs.tkinter;
          };
        }
      )
      (import ./python-overrides.nix { inherit pkgs python; })
    ]
  );

  pythonEnv = pythonSet.mkVirtualEnv "rvc-${acceleration}-python-env" (
    workspace.deps.default // { tkinter = [ ]; }
  );

  rvcSource = pkgs.stdenvNoCC.mkDerivation {
    pname = "rvc-source";
    version = "unstable-${inputs.rvc-src.shortRev or "pinned"}";
    src = rvc-src;
    patches = [ ./patches/safe-training-subprocesses.patch ];
    dontBuild = true;

    postPatch = ''

      # Normalise patched files with mixed line endings; unrelated source files
      # remain byte-for-byte identical to upstream.
      sed -i 's/\r$//' infer/hubert.py realtime_gui.py

      # Every remaining source change lives as a regular patch file generated
      # by nix/patches/generate_patches.py (see CONTRIBUTING.md). GNU
      # patch fails the build on a hunk that no longer applies, which keeps
      # the previous --replace-fail contract: an upstream update forces a
      # deliberate patch review instead of silently degrading.
      apply_patch_set() {
        local patch_dir="$1"
        for patch_file in "$patch_dir"/*.patch; do
          echo "applying $(basename "$patch_file")"
          patch -p1 --batch --forward <"$patch_file"
        done
      }
      apply_patch_set ${./patches/rvc}
      ${lib.optionalString (acceleration == "cuda") ''

        apply_patch_set ${./patches/cuda}
      ''}
    '';

    installPhase = ''

      runHook preInstall
      mkdir -p $out/share/rvc
      cp -a . $out/share/rvc/
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''

      ${python.interpreter} ${./tests/checkpoint_ast_policy.py} "$out/share/rvc"

      checkpoint_test_dir="$TMPDIR/rvc-checkpoint-security"
      mkdir -p "$checkpoint_test_dir/data" "$checkpoint_test_dir/numba"
      NUMBA_CACHE_DIR="$checkpoint_test_dir/numba" \
        PYTHONDONTWRITEBYTECODE=1 \
        RVC_DATA_DIR="$checkpoint_test_dir/data" \
        ${pythonEnv}/bin/python ${./tests/checkpoint_runtime_security.py} \
          "$out/share/rvc" "$checkpoint_test_dir"

      ${lib.optionalString (models != null) ''

        model_test_dir="$TMPDIR/inference-model-forward"
        mkdir -p \
          "$model_test_dir/assets" \
          "$model_test_dir/cache/numba"
        ln -s ${models}/assets/hubert_base "$model_test_dir/assets/hubert_base"
        ln -s ${models}/assets/rmvpe "$model_test_dir/assets/rmvpe"

        HF_HUB_OFFLINE=1 \
          NUMBA_CACHE_DIR="$model_test_dir/cache/numba" \
          PYTHONDONTWRITEBYTECODE=1 \
          PYTHONPATH="$out/share/rvc" \
          RVC_CACHE_DIR="$model_test_dir/cache" \
          RVC_DATA_DIR="$model_test_dir" \
          TRANSFORMERS_OFFLINE=1 \
          ${pythonEnv}/bin/python -P ${./tests/inference_model_forward.py} cpu

        # The realtime synthesizer forward (net_g through infer/vc/pipeline
        # and rtrvc.infer) runs whenever the bundled model set contains an
        # official pretrained voice checkpoint.
        if [ -f "${models}/assets/pretrained_v2/f0G40k.pth" ]; then
          HF_HUB_OFFLINE=1 \
            NUMBA_CACHE_DIR="$model_test_dir/cache/numba" \
            PYTHONDONTWRITEBYTECODE=1 \
            PYTHONPATH="$out/share/rvc" \
            RVC_CACHE_DIR="$model_test_dir/cache" \
            RVC_DATA_DIR="$model_test_dir" \
            TRANSFORMERS_OFFLINE=1 \
            ${pythonEnv}/bin/python -P ${./tests/realtime_infer_forward.py} \
              "${models}/assets/pretrained_v2/f0G40k.pth" cpu
        fi
      ''}

      ${python.interpreter} ${./tests/training_subprocess_security.py} \
        "$out/share/rvc/webui.py"
    '';
  };

  launcherParts = import ./launcher.nix {
    inherit
      acceleration
      lib
      models
      pkgs
      pythonEnv
      rvcSource
      ;
  };
in
pkgs.symlinkJoin {
  name = "rvc-${acceleration}${modelSuffix}";
  paths = launcherParts.commands ++ [ launcherParts.desktopItem ];
  passthru = {
    inherit
      acceleration
      models
      ;
  };
  meta = {
    description = "Retrieval-based Voice Conversion (${acceleration}) packaged with uv2nix";
    homepage = "https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI";
    license = lib.licenses.mit;
    mainProgram = "rvc-realtime";
    platforms = [ "x86_64-linux" ];
  };
}
