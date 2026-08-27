# All flake checks live here so flake.nix stays a map of outputs and a new
# check has exactly one home. Checks must run without specialized hardware;
# hardware-bound acceptance lives in nix/tests/*-live.sh.
{
  consumerPkgs,
  inputs,
  modelAssets,
  pkgs,
  self,
  treefmtEval,
  rvcPackages,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expectedAppNames = [
    "cli"
    "cli-cuda118"
    "cli-cuda128"
    "default"
    "pymss"
    "pymss-cuda118"
    "pymss-cuda128"
    "realtime"
    "realtime-cuda118"
    "realtime-cuda128"
    "web"
    "web-all"
    "web-all-cuda118"
    "web-all-cuda128"
    "web-cuda118"
    "web-cuda128"
  ];
  expectedPackageNames = [
    "cpu"
    "cpu-all"
    "cuda118"
    "cuda118-all"
    "cuda128"
    "cuda128-all"
    "default"
    "models-all"
    "models-inference"
    "models-mute"
    "models-pretrained-v1"
    "models-pretrained-v2"
    "models-pymss"
    "models-training"
  ];
  expectedOverlayNames = [
    "rvc"
    "rvc-cpu"
    "rvc-cpu-all"
    "rvc-cuda118"
    "rvc-cuda118-all"
    "rvc-cuda128"
    "rvc-cuda128-all"
    "rvc-models-all"
    "rvc-models-inference"
    "rvc-models-mute"
    "rvc-models-pretrained-v1"
    "rvc-models-pretrained-v2"
    "rvc-models-pymss"
    "rvc-models-training"
  ];
  mkExpectedAppPrograms =
    backend:
    let
      suffix = if backend == "cpu" then "" else "-${backend}";
      backendPackages = rvcPackages.${backend};
    in
    {
      "realtime${suffix}" = "${backendPackages.inferenceModels}/bin/rvc-realtime";
      "web${suffix}" = "${backendPackages.inferenceModels}/bin/rvc-web";
      "web-all${suffix}" = "${backendPackages.allModels}/bin/rvc-web";
      "cli${suffix}" = "${backendPackages.inferenceModels}/bin/rvc-cli";
      "pymss${suffix}" = "${backendPackages.pymssModels}/bin/pymss";
    };
  expectedAppPrograms = pkgs.lib.foldl' (
    programs: backend: programs // mkExpectedAppPrograms backend
  ) { } (builtins.attrNames rvcPackages);
  expectedRuntimePackages = {
    cpu = rvcPackages.cpu.inferenceModels;
    cpu-all = rvcPackages.cpu.allModels;
    cuda118 = rvcPackages.cuda118.inferenceModels;
    cuda118-all = rvcPackages.cuda118.allModels;
    cuda128 = rvcPackages.cuda128.inferenceModels;
    cuda128-all = rvcPackages.cuda128.allModels;
    default = rvcPackages.cpu.inferenceModels;
  };
  expectedModelPackages = {
    models-all = modelAssets.all;
    models-inference = modelAssets.inference;
    models-mute = modelAssets.mute;
    models-pretrained-v1 = modelAssets.pretrained-v1;
    models-pretrained-v2 = modelAssets.pretrained-v2;
    models-pymss = modelAssets.pymss;
    models-training = modelAssets.training;
  };
  appNamesJson = pkgs.writeText "rvc-app-names.json" (
    builtins.toJSON (builtins.attrNames self.apps.${system})
  );
  packageNamesJson = pkgs.writeText "rvc-package-names.json" (
    builtins.toJSON (builtins.attrNames self.packages.${system})
  );
  pymssAssetPaths = modelAssets.pymss.assetPaths;
  pymssModelNames = map baseNameOf pymssAssetPaths;
  fakePymssModels = pkgs.runCommand "rvc-fake-pymss-models" { passthru.modelChecks = [ ]; } ''
    ${pkgs.lib.concatMapStringsSep "\n" (
      path: ''install -Dm444 /dev/null "$out/assets/${path}"''
    ) pymssAssetPaths}
  '';
  fakePymssPackage = rvcPackages.cpu.noModels.override { models = fakePymssModels; };
  oldModelSet = pkgs.runCommand "rvc-old-models-fixture" { } ''
    mkdir -p "$out/assets/hubert_base"
    touch "$out/assets/hubert_base/config.json"
  '';
  emptyModelsPackage = rvcPackages.cpu.noModels.override { models = [ ]; };
  combinedModelsPackage = rvcPackages.cpu.noModels.override {
    models = [
      modelAssets.inference
      fakePymssModels
    ];
  };
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
    models:
    (builtins.tryEval ((rvcPackages.cpu.noModels.override { inherit models; }).drvPath)).success;
  overlayNames = builtins.filter (pkgs.lib.hasPrefix "rvc") (builtins.attrNames consumerPkgs);
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
  public-interface =
    assert
      builtins.attrNames rvcPackages == [
        "cpu"
        "cuda118"
        "cuda128"
      ];
    assert
      builtins.attrNames rvcPackages.cpu == [
        "allModels"
        "inferenceModels"
        "noModels"
        "pymssModels"
      ];
    assert builtins.attrNames self.packages.${system} == expectedPackageNames;
    assert builtins.attrNames self.apps.${system} == expectedAppNames;
    assert pkgs.lib.all (
      name: self.packages.${system}.${name}.drvPath == expectedRuntimePackages.${name}.drvPath
    ) (builtins.attrNames expectedRuntimePackages);
    assert pkgs.lib.all (
      name: self.packages.${system}.${name}.drvPath == expectedModelPackages.${name}.drvPath
    ) (builtins.attrNames expectedModelPackages);
    assert pkgs.lib.all (name: self.apps.${system}.${name}.program == expectedAppPrograms.${name}) (
      builtins.attrNames expectedAppPrograms
    );
    assert self.apps.${system}.default.program == self.apps.${system}.realtime.program;
    assert
      builtins.attrNames self.nixosModules == [
        "default"
        "rvc"
      ];
    assert builtins.attrNames self.overlays == [ "default" ];
    assert overlayNames == expectedOverlayNames;
    pkgs.runCommand "rvc-public-interface" { } ''touch "$out"'';

  cpu-smoke = pkgs.runCommand "rvc-cpu-smoke" { } ''

    export HOME="$TMPDIR/home"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME"

    user_link_target="$TMPDIR/user-owned-missing"
    old_source_root="/nix/store/00000000000000000000000000000000-rvc-source-unstable-old/share/rvc"
    data_root="$XDG_DATA_HOME/rvc"
    mkdir -p "$data_root/assets/pymss_weights/karaoke"
    ln -s "$old_source_root/i18n" "$data_root/i18n"
    ln -s "$old_source_root/assets/pymss_weights/config_mel_band_roformer_karaoke.yaml" \
      "$data_root/assets/pymss_weights/config_mel_band_roformer_karaoke.yaml"
    ln -s "$user_link_target" "$data_root/train"
    ln -s "$user_link_target" \
      "$data_root/assets/pymss_weights/model_bs_roformer_ep_317_sdr_12.9755.yaml"
    ln -s "$user_link_target" \
      "$data_root/assets/pymss_weights/karaoke/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.yaml"

    ${rvcPackages.cpu.noModels}/bin/rvc-doctor
    ${rvcPackages.cpu.noModels}/bin/rvc-cli --help >/dev/null
    ${rvcPackages.cpu.noModels}/bin/rvc-python -c 'import configs.config' >/dev/null
    ${rvcPackages.cpu.noModels}/bin/pymss list --json >/dev/null
    RVC_SMOKE_TEST=1 ${rvcPackages.cpu.noModels}/bin/rvc-web --noautoopen
    RVC_SMOKE_TEST=1 ${rvcPackages.cpu.noModels}/bin/rvc-realtime

    readarray -t launcher_env < <(
      ${rvcPackages.cpu.noModels}/bin/rvc-launcher-cpu env
    )
    source_dir="''${launcher_env[0]}"
    test "$(readlink "$data_root/i18n")" = "$source_dir/i18n"
    test "$(readlink \
      "$data_root/assets/pymss_weights/config_mel_band_roformer_karaoke.yaml")" = \
      "$source_dir/assets/pymss_weights/config_mel_band_roformer_karaoke.yaml"
    test -L "$XDG_DATA_HOME/rvc/assets/pymss_weights/karaoke/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.yaml"
    test -L "$XDG_DATA_HOME/rvc/assets/pymss_weights/reverb_echo_control/dereverb/dereverb_mel_band_roformer_anvuew_sdr_19.1729.yaml"
    test "$(readlink "$data_root/train")" = "$user_link_target"
    test "$(readlink \
      "$data_root/assets/pymss_weights/model_bs_roformer_ep_317_sdr_12.9755.yaml")" = \
      "$user_link_target"
    test "$(readlink \
      "$data_root/assets/pymss_weights/karaoke/model_mel_band_roformer_karaoke_aufr33_viperx_sdr_10.1956.yaml")" = \
      "$user_link_target"

    # Valid and dangling links created by an older packaged source must both
    # be refreshed, while the unrelated user-owned dangling link above stays
    # untouched.
    ln -sfn "$old_source_root/train" "$data_root/train"
    ${rvcPackages.cpu.noModels}/bin/rvc-doctor >/dev/null
    test "$(readlink "$data_root/train")" = "$source_dir/train"

    mkdir -p "$TMPDIR/relative-test"
    cd "$TMPDIR/relative-test"
    path_report="$({
      RVC_DATA_DIR=relative-data \
      RVC_CONFIG_DIR=relative-config \
      RVC_CACHE_DIR=relative-cache \
      ${rvcPackages.cpu.noModels}/bin/rvc-doctor
    })"
    printf '%s\n' "$path_report" | grep -F "RVC data:    $TMPDIR/relative-test/relative-data"
    printf '%s\n' "$path_report" | grep -F "RVC config:  $TMPDIR/relative-test/relative-config"

    touch "$out"
  '';

  pymss-models-smoke = pkgs.runCommand "rvc-pymss-models-smoke" { } ''
    ${pkgs.lib.concatMapStringsSep "\n" (path: ''
      test -L "${modelAssets.pymss}/assets/${path}"
      test -f "${modelAssets.pymss}/assets/${path}"
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
    mkdir -p \
      "$HOME" \
      "$RVC_DATA_DIR/assets/hubert_base" \
      "$RVC_DATA_DIR/assets/rmvpe"

    old_model_root="/nix/store/00000000000000000000000000000000-custom-models-old"
    ln -s ${oldModelSet}/assets/hubert_base/config.json \
      "$RVC_DATA_DIR/assets/hubert_base/config.json"
    ln -s "$old_model_root/assets/hubert_base/preprocessor_config.json" \
      "$RVC_DATA_DIR/assets/hubert_base/preprocessor_config.json"
    printf 'user-owned-rmvpe\n' >"$RVC_DATA_DIR/assets/rmvpe/rmvpe.pt"
    ${rvcPackages.cpu.inferenceModels}/bin/rvc-doctor

    grep -Fx 'user-owned-rmvpe' "$RVC_DATA_DIR/assets/rmvpe/rmvpe.pt"
    test "$(readlink "$RVC_DATA_DIR/assets/hubert_base/config.json")" = \
      "${modelAssets.inference}/assets/hubert_base/config.json"
    test "$(readlink "$RVC_DATA_DIR/assets/hubert_base/preprocessor_config.json")" = \
      "${modelAssets.inference}/assets/hubert_base/preprocessor_config.json"
    test -L "$RVC_DATA_DIR/assets/hubert_base/pytorch_model.bin"
    test "$(readlink "$RVC_DATA_DIR/assets/hubert_base/pytorch_model.bin")" = \
      "${modelAssets.inference}/assets/hubert_base/pytorch_model.bin"

    touch "$RVC_DATA_DIR/assets/weights/personal.pth"
    touch "$RVC_DATA_DIR/logs/personal.log"
    ${rvcPackages.cpu.inferenceModels}/bin/rvc-cli --help >/dev/null
    test -f "$RVC_DATA_DIR/assets/weights/personal.pth"
    test -f "$RVC_DATA_DIR/logs/personal.log"
    touch "$out"
  '';

  nixos-module = import ./module-test.nix {
    inherit pkgs;
    nixosSystem = inputs.nixpkgs.lib.nixosSystem;
    nixosModule = self.nixosModules.default;
    cpuPackage = rvcPackages.cpu.inferenceModels;
    cudaPackage = rvcPackages.cuda118.inferenceModels;
  };

  overlay-interface =
    assert
      self.packages.${pkgs.stdenv.hostPlatform.system}.default.drvPath
      == rvcPackages.cpu.inferenceModels.drvPath;
    assert consumerPkgs.rvc.drvPath == rvcPackages.cpu.inferenceModels.drvPath;
    assert consumerPkgs.rvc.acceleration == "cpu";
    assert consumerPkgs.rvc.models.drvPath == modelAssets.inference.drvPath;
    assert consumerPkgs.rvc.meta.mainProgram == "rvc-realtime";
    assert consumerPkgs.rvc-cpu.drvPath == rvcPackages.cpu.inferenceModels.drvPath;
    assert consumerPkgs.rvc-cpu.models.drvPath == modelAssets.inference.drvPath;
    assert consumerPkgs.rvc-cuda118.drvPath == rvcPackages.cuda118.inferenceModels.drvPath;
    assert consumerPkgs.rvc-cuda128.drvPath == rvcPackages.cuda128.inferenceModels.drvPath;
    assert consumerPkgs.rvc-cuda118.models.drvPath == modelAssets.inference.drvPath;
    assert consumerPkgs.rvc-cuda128.models.drvPath == modelAssets.inference.drvPath;
    assert consumerPkgs.rvc-cpu-all.models.drvPath == modelAssets.all.drvPath;
    assert consumerPkgs.rvc-cuda118-all.models.drvPath == modelAssets.all.drvPath;
    assert consumerPkgs.rvc-cuda128-all.models.drvPath == modelAssets.all.drvPath;
    assert modelAssets.inference.modelChecks == [ "hubert-rmvpe-forward" ];
    assert modelAssets.pymss.modelChecks == [ ];
    assert modelAssets.training.modelChecks == [ ];
    assert
      modelAssets.all.modelChecks == [
        "hubert-rmvpe-forward"
        "realtime-synth-forward"
      ];
    assert consumerPkgs.rvc-models-inference.drvPath == modelAssets.inference.drvPath;
    assert consumerPkgs.rvc-models-pretrained-v1.drvPath == modelAssets.pretrained-v1.drvPath;
    assert consumerPkgs.rvc-models-pretrained-v2.drvPath == modelAssets.pretrained-v2.drvPath;
    assert consumerPkgs.rvc-models-mute.drvPath == modelAssets.mute.drvPath;
    assert consumerPkgs.rvc-models-pymss.drvPath == modelAssets.pymss.drvPath;
    assert consumerPkgs.rvc-models-training.drvPath == modelAssets.training.drvPath;
    assert consumerPkgs.rvc-models-all.drvPath == modelAssets.all.drvPath;
    pkgs.runCommand "rvc-overlay-interface" { } ''touch "$out"'';

  model-metadata-contract =
    assert modelPackageEvaluates fakePymssModels;
    assert emptyModelsPackage.drvPath == rvcPackages.cpu.noModels.drvPath;
    assert emptyModelsPackage.models == null;
    assert
      combinedModelsPackage.models.modelChecks == [
        "hubert-rmvpe-forward"
      ];
    assert !modelPackageEvaluates modelSetWithoutChecks;
    assert !modelPackageEvaluates modelSetWithNonListChecks;
    assert !modelPackageEvaluates modelSetWithNonStringCheck;
    assert !modelPackageEvaluates modelSetWithUnknownCheck;
    pkgs.runCommand "rvc-model-metadata-contract" { } ''
      test -f ${combinedModelsPackage.models}/assets/hubert_base/config.json
      test -f ${combinedModelsPackage.models}/assets/${builtins.head pymssAssetPaths}
      touch "$out"
    '';

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
      ${appNamesJson} \
      ${packageNamesJson}
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
