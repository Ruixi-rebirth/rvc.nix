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
let
  appNamesJson = pkgs.writeText "rvc-app-names.json" (
    builtins.toJSON (builtins.attrNames self.apps.${pkgs.stdenv.hostPlatform.system})
  );
  pymssAssetPaths = modelSets.pymss.assetPaths;
  pymssModelNames = map baseNameOf pymssAssetPaths;
  fakePymssModels = pkgs.runCommand "rvc-fake-pymss-models" { passthru.modelChecks = [ ]; } ''
    ${pkgs.lib.concatMapStringsSep "\n" (
      path: ''install -Dm444 /dev/null "$out/assets/${path}"''
    ) pymssAssetPaths}
  '';
  fakePymssPackage = variants.cpu.override { models = fakePymssModels; };
  mkModelSetFixture =
    {
      modelChecks ? null,
      name,
    }:
    pkgs.runCommand "rvc-model-set-${name}"
      (pkgs.lib.optionalAttrs (modelChecks != null) {
        passthru = { inherit modelChecks; };
      })
      ''
        mkdir -p "$out/assets"
      '';
  modelSetWithoutChecks = mkModelSetFixture { name = "without-checks"; };
  modelSetWithNonListChecks = mkModelSetFixture {
    name = "with-non-list-checks";
    modelChecks = "hubert-rmvpe-forward";
  };
  modelSetWithNonStringCheck = mkModelSetFixture {
    name = "with-non-string-check";
    modelChecks = [ 1 ];
  };
  modelSetWithUnknownCheck = mkModelSetFixture {
    name = "with-unknown-check";
    modelChecks = [ "unknown-check" ];
  };
  modelPackageEvaluates =
    models: (builtins.tryEval ((variants.cpu.override { inherit models; }).drvPath)).success;
  # `nix flake check path:.` includes the checkout metadata in `self`.
  # treefmt creates its own temporary Git repository, so exclude only the
  # nested metadata while keeping every project file in the format check.
  treefmtSource = pkgs.lib.cleanSourceWith {
    name = "rvc-treefmt-source";
    src = self;
    filter = path: _type: baseNameOf path != ".git";
  };
in
{
  cpu-smoke = pkgs.runCommand "rvc-cpu-smoke" { } ''

    export HOME="$TMPDIR/home"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME"

    user_link_target="$TMPDIR/user-owned-missing"
    data_root="$XDG_DATA_HOME/rvc"
    mkdir -p "$data_root/assets/pymss_weights/karaoke"
    ln -s "$user_link_target" "$data_root/train"
    ln -s "$user_link_target" \
      "$data_root/assets/pymss_weights/model_bs_roformer_ep_317_sdr_12.9755.yaml"
    ln -s "$user_link_target" \
      "$data_root/assets/pymss_weights/karaoke/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.yaml"

    ${variants.cpu}/bin/rvc-doctor
    ${variants.cpu}/bin/rvc-cli --help >/dev/null
    ${variants.cpu}/bin/rvc-python -c 'import configs.config' >/dev/null
    ${variants.cpu}/bin/pymss list --json >/dev/null
    RVC_SMOKE_TEST=1 ${variants.cpu}/bin/rvc-web --noautoopen
    RVC_SMOKE_TEST=1 ${variants.cpu}/bin/rvc-realtime

    test -L "$XDG_DATA_HOME/rvc/assets/pymss_weights/karaoke/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.yaml"
    test -L "$XDG_DATA_HOME/rvc/assets/pymss_weights/reverb_echo_control/dereverb/dereverb_mel_band_roformer_anvuew_sdr_19.1729.yaml"
    test "$(readlink "$data_root/train")" = "$user_link_target"
    test "$(readlink \
      "$data_root/assets/pymss_weights/model_bs_roformer_ep_317_sdr_12.9755.yaml")" = \
      "$user_link_target"
    test "$(readlink \
      "$data_root/assets/pymss_weights/karaoke/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.yaml")" = \
      "$user_link_target"

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

  pymss-models-smoke = pkgs.runCommand "rvc-pymss-models-smoke" { } ''
    ${pkgs.lib.concatMapStringsSep "\n" (path: ''
      test -L "${modelSets.pymss}/assets/${path}"
      test -f "${modelSets.pymss}/assets/${path}"
    '') pymssAssetPaths}
    touch "$out"
  '';

  pymss-launcher-smoke = pkgs.runCommand "rvc-pymss-launcher-smoke" { } ''
    export HOME="$TMPDIR/home"
    export RVC_CACHE_DIR="$TMPDIR/cache"
    export RVC_CONFIG_DIR="$TMPDIR/config"
    export RVC_DATA_DIR="$TMPDIR/data"
    mkdir -p "$HOME"

    ${fakePymssPackage}/bin/rvc-python \
      ${./tests/pymss_models.py} \
      ${pkgs.lib.escapeShellArgs pymssModelNames}
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
    cudaPackage = variants.cuda118;
  };

  overlay-interface =
    assert
      self.packages.${pkgs.stdenv.hostPlatform.system}.default.drvPath
      == variants.cpu-with-models.drvPath;
    assert consumerPkgs.rvc.drvPath == variants.cpu-with-models.drvPath;
    assert consumerPkgs.rvc.acceleration == "cpu";
    assert consumerPkgs.rvc.models.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc.meta.mainProgram == "rvc-realtime";
    assert consumerPkgs.rvc-cpu-with-models.drvPath == variants.cpu-with-models.drvPath;
    assert consumerPkgs.rvc-cpu-with-models.models.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-cuda118.drvPath == variants.cuda118.drvPath;
    assert consumerPkgs.rvc-cuda128.drvPath == variants.cuda128.drvPath;
    assert consumerPkgs.rvc-cuda118-with-models.models.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-cuda128-with-models.models.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-cpu-with-all-models.models.drvPath == modelSets.all.drvPath;
    assert consumerPkgs.rvc-cuda118-with-all-models.models.drvPath == modelSets.all.drvPath;
    assert consumerPkgs.rvc-cuda128-with-all-models.models.drvPath == modelSets.all.drvPath;
    assert modelSets.inference.modelChecks == [ "hubert-rmvpe-forward" ];
    assert modelSets.pymss.modelChecks == [ ];
    assert modelSets.training.modelChecks == [ ];
    assert
      modelSets.all.modelChecks == [
        "hubert-rmvpe-forward"
        "realtime-synth-forward"
      ];
    assert consumerPkgs.rvc-models-inference.drvPath == modelSets.inference.drvPath;
    assert consumerPkgs.rvc-models-pretrained-v1.drvPath == modelSets.pretrained-v1.drvPath;
    assert consumerPkgs.rvc-models-pretrained-v2.drvPath == modelSets.pretrained-v2.drvPath;
    assert consumerPkgs.rvc-models-mute.drvPath == modelSets.mute.drvPath;
    assert consumerPkgs.rvc-models-pymss.drvPath == modelSets.pymss.drvPath;
    assert consumerPkgs.rvc-models-training.drvPath == modelSets.training.drvPath;
    assert consumerPkgs.rvc-models-all.drvPath == modelSets.all.drvPath;
    pkgs.runCommand "rvc-overlay-interface" { } ''touch "$out"'';

  model-metadata-contract =
    assert modelPackageEvaluates fakePymssModels;
    assert !modelPackageEvaluates modelSetWithoutChecks;
    assert !modelPackageEvaluates modelSetWithNonListChecks;
    assert !modelPackageEvaluates modelSetWithNonStringCheck;
    assert !modelPackageEvaluates modelSetWithUnknownCheck;
    pkgs.runCommand "rvc-model-metadata-contract" { } ''touch "$out"'';

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

    ${pkgs.python312}/bin/python ${./tests/pyproject_sync.py} ${self} ${inputs.rvc-src}
    touch "$out"
  '';
  readme-upstream-revision = pkgs.runCommand "rvc-readme-upstream-revision" { } ''

    ${pkgs.python312}/bin/python ${./tests/readme_upstream_revision.py} ${self}
    touch "$out"
  '';
  documented-apps = pkgs.runCommand "rvc-documented-apps" { } ''

    ${pkgs.python312}/bin/python \
      ${./tests/documented_apps.py} \
      ${self} \
      ${appNamesJson}
    touch "$out"
  '';
  python-locks = pkgs.runCommand "rvc-python-locks" { nativeBuildInputs = [ pkgs.uv ]; } ''

    export UV_CACHE_DIR="$TMPDIR/uv-cache"
    export UV_PYTHON_DOWNLOADS=never
    unset SSL_CERT_FILE

    cd ${self}/python/cpu
    uv lock --check --offline --python ${pkgs.python312}/bin/python

    cd ${self}/python/cuda118
    uv lock --check --offline --python ${pkgs.python312}/bin/python

    cd ${self}/python/cuda128
    uv lock --check --offline --python ${pkgs.python312}/bin/python

    touch "$out"
  '';
  treefmt = treefmtEval.config.build.check treefmtSource;
}
