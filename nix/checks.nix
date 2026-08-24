# All flake checks live here so flake.nix stays a map of outputs and a new
# check has exactly one home. Checks must run without specialized hardware;
# hardware-bound acceptance lives in nix/tests/*-live.sh.
{
  consumerPkgs,
  inputs,
  modelSets,
  pkgs,
  self,
  treefmtEval,
  variants,
}:
{
  cpu-smoke = pkgs.runCommand "rvc-cpu-smoke" { } ''

    export HOME="$TMPDIR/home"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME"
    ${variants.cpu}/bin/rvc-doctor
    ${variants.cpu}/bin/rvc-cli --help >/dev/null
    ${variants.cpu}/bin/pymss list --json >/dev/null
    RVC_SMOKE_TEST=1 ${variants.cpu}/bin/rvc-web --noautoopen
    RVC_SMOKE_TEST=1 ${variants.cpu}/bin/rvc-realtime

    mkdir -p "$TMPDIR/relative-test"
    cd "$TMPDIR/relative-test"
    path_report="$({
      RVC_DATA_DIR=relative-data \
      RVC_CONFIG_DIR=relative-config \
      RVC_CACHE_DIR=relative-cache \
      ${variants.cpu}/bin/rvc-doctor
    })"
    printf '%s\n' "$path_report" | grep -F "RVC data:    $TMPDIR/relative-test/relative-data"
    printf '%s\n' "$path_report" | grep -F "RVC config:  $TMPDIR/relative-test/relative-config"

    touch "$out"
  '';

  cpu-models-smoke = pkgs.runCommand "rvc-cpu-models-smoke" { } ''

    export HOME="$TMPDIR/home"
    export RVC_CACHE_DIR="$TMPDIR/cache"
    export RVC_CONFIG_DIR="$TMPDIR/config"
    export RVC_DATA_DIR="$TMPDIR/data"
    mkdir -p "$HOME" "$RVC_DATA_DIR/assets/rmvpe"

    printf 'user-owned-rmvpe\n' >"$RVC_DATA_DIR/assets/rmvpe/rmvpe.pt"
    ${variants.cpu-with-models}/bin/rvc-doctor

    grep -Fx 'user-owned-rmvpe' "$RVC_DATA_DIR/assets/rmvpe/rmvpe.pt"
    test -L "$RVC_DATA_DIR/assets/hubert_base/pytorch_model.bin"
    test "$(readlink "$RVC_DATA_DIR/assets/hubert_base/pytorch_model.bin")" = \
      "${modelSets.inference}/assets/hubert_base/pytorch_model.bin"

    touch "$RVC_DATA_DIR/assets/weights/personal.pth"
    touch "$RVC_DATA_DIR/logs/personal.log"
    ${variants.cpu-with-models}/bin/rvc-cli --help >/dev/null
    test -f "$RVC_DATA_DIR/assets/weights/personal.pth"
    test -f "$RVC_DATA_DIR/logs/personal.log"
    touch "$out"
  '';

  nixos-module = import ./module-test.nix {
    inherit pkgs;
    nixosSystem = inputs.nixpkgs.lib.nixosSystem;
    nixosModule = self.nixosModules.default;
    cpuPackage = variants.cpu-with-models;
    cudaPackage = variants.cuda;
  };

  overlay-interface =
    assert consumerPkgs.rvc.drvPath == variants.cpu.drvPath;
    assert consumerPkgs.rvc.acceleration == "cpu";
    assert consumerPkgs.rvc.meta.mainProgram == "rvc-realtime";
    assert consumerPkgs.rvc-cpu-with-models.drvPath == variants.cpu-with-models.drvPath;
    assert consumerPkgs.rvc-cpu-with-models.models.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-cuda.drvPath == variants.cuda.drvPath;
    assert consumerPkgs.rvc-cuda-with-models.models.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-cpu-with-all-models.models.drvPath == modelSets.all.drvPath;
    assert consumerPkgs.rvc-cuda-with-all-models.models.drvPath == modelSets.all.drvPath;
    assert consumerPkgs.rvc-models-inference.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-models-training.drvPath == modelSets.training.drvPath;
    assert consumerPkgs.rvc-models-all.drvPath == modelSets.all.drvPath;
    pkgs.runCommand "rvc-overlay-interface" { } ''touch "$out"'';
  # The patch files must be reproducible from the pinned upstream
  # source. Regenerate them from the rvc-src flake input (already
  # fetched during evaluation; no network) and require byte equality,
  # so the checked-in patch set can never drift from flake.lock.
  patches-in-sync =
    pkgs.runCommand "rvc-patches-in-sync"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.python312
        ];
      }
      ''

        ${pkgs.python312}/bin/python \
          ${./patches}/generate_patches.py \
          --repo-root ${self} \
          --src-dir ${inputs.rvc-src} \
          --verify
        touch "$out"
      '';

  pyproject-sync = pkgs.runCommand "rvc-pyproject-sync" { } ''

    ${pkgs.python312}/bin/python ${./tests/pyproject_sync.py} ${self}
    touch "$out"
  '';
  python-locks = pkgs.runCommand "rvc-python-locks" { nativeBuildInputs = [ pkgs.uv ]; } ''

    export UV_CACHE_DIR="$TMPDIR/uv-cache"
    export UV_PYTHON_DOWNLOADS=never
    unset SSL_CERT_FILE

    cd ${self}
    uv lock --check --offline --python ${pkgs.python312}/bin/python

    cd ${self}/python/cpu
    uv lock --check --offline --python ${pkgs.python312}/bin/python

    touch "$out"
  '';
  treefmt = treefmtEval.config.build.check self;
}
