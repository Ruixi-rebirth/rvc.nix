# Launcher and command wrappers for the RVC packages. Kept separate from
# package.nix (Python environment, source patching, and install checks) so
# launcher changes stay reviewable without the uv2nix machinery around them.
{
  acceleration,
  lib,
  models,
  pkgs,
  pythonEnv,
  rvcSource,
}:

let
  launcher = pkgs.writeShellApplication {
    name = "rvc-launcher-${acceleration}";
    runtimeInputs =
      (with pkgs; [
        coreutils
        ffmpeg
      ])
      ++ lib.optionals (models != null) [ pkgs.findutils ];
    text = ''

      mode="''${1:-realtime}"
      if [ "$#" -gt 0 ]; then shift; fi

      ui_language="''${RVC_UI_LANGUAGE:-}"
      if [ -n "$ui_language" ]; then
        export LC_ALL="$ui_language"
      fi

      source_dir=${rvcSource}/share/rvc

      # Internal: report the resolved source tree and Python environment for
      # the live acceptance tests. Handled before any directory creation or
      # model population, so the query itself has no side effects and cannot
      # fail on environment conditions unrelated to the paths it reports.
      if [ "$mode" = "env" ]; then
        printf '%s\n' "$source_dir"
        printf '%s\n' "${pythonEnv}/bin/python"
        exit 0
      fi

      data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
      config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
      cache_home="''${XDG_CACHE_HOME:-$HOME/.cache}"
      data_dir="''${RVC_DATA_DIR:-$data_home/rvc}"
      config_dir="''${RVC_CONFIG_DIR:-$config_home/rvc}"
      cache_dir="''${RVC_CACHE_DIR:-$cache_home/rvc}"
      ${lib.optionalString (acceleration == "cuda") ''

        driver_library_path="''${RVC_DRIVER_LIBRARY_PATH:-/run/opengl-driver/lib}"
      ''}

      # Resolve once, before changing directory. Relative overrides are relative
      # to the caller's working directory and never become data/data by accident.
      data_dir="$(realpath --canonicalize-missing -- "$data_dir")"
      config_dir="$(realpath --canonicalize-missing -- "$config_dir")"
      cache_dir="$(realpath --canonicalize-missing -- "$cache_dir")"

      mkdir -p \
        "$config_dir" \
        "$cache_dir" \
        "$cache_dir/tmp" \
        "$data_dir/logs" \
        "$data_dir/assets/hubert_base" \
        "$data_dir/assets/indices" \
        "$data_dir/assets/pretrained" \
        "$data_dir/assets/pretrained_v2" \
        "$data_dir/assets/pymss_weights" \
        "$data_dir/assets/rmvpe" \
        "$data_dir/assets/weights"

      for code_dir in i18n train; do
        if [ ! -e "$data_dir/$code_dir" ]; then
          ln -s "$source_dir/$code_dir" "$data_dir/$code_dir"
        fi
      done

      # A non-matching glob must expand to nothing: without nullglob the loop
      # would run once with the literal pattern and create a dangling link.
      shopt -s nullglob
      for config_file in "$source_dir"/assets/pymss_weights/*.yaml; do
        config_name="$(basename "$config_file")"
        if [ ! -e "$data_dir/assets/pymss_weights/$config_name" ]; then
          ln -s "$config_file" "$data_dir/assets/pymss_weights/$config_name"
        fi
      done

      ${lib.optionalString (models != null) ''

        populate_model_tree() {
          model_root="$1"
          destination_root="$2"

          if [ ! -d "$model_root" ]; then
            return
          fi

          while IFS= read -r -d "" model_file; do
            relative_path="''${model_file#"$model_root"/}"
            destination="$destination_root/$relative_path"
            mkdir -p "$(dirname "$destination")"
            if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
              ln -s "$model_file" "$destination"
            fi
          done < <(find -L "$model_root" -type f -print0)
        }

        # Populate only missing files; user-owned data always wins and mutable
        # directories never inherit read-only Nix store permissions.
        populate_model_tree ${models}/assets "$data_dir/assets"
        populate_model_tree ${models}/logs "$data_dir/logs"
      ''}

      export RVC_DATA_DIR="$data_dir"
      export RVC_CONFIG_DIR="$config_dir"
      export RVC_CACHE_DIR="$cache_dir"
      export HF_HOME="''${HF_HOME-$cache_dir/huggingface}"
      export HF_HUB_DISABLE_TELEMETRY="''${HF_HUB_DISABLE_TELEMETRY-1}"
      export GRADIO_ANALYTICS_ENABLED="''${GRADIO_ANALYTICS_ENABLED-False}"
      export GRADIO_TEMP_DIR="''${GRADIO_TEMP_DIR-$cache_dir/gradio}"
      export MPLCONFIGDIR="''${MPLCONFIGDIR-$cache_dir/matplotlib}"
      export NUMBA_CACHE_DIR="''${NUMBA_CACHE_DIR-$cache_dir/numba}"
      export ORT_DISABLE_ALL_TELEMETRY="''${ORT_DISABLE_ALL_TELEMETRY-1}"
      export PYMSS_MODEL_DIR="''${PYMSS_MODEL_DIR-$data_dir/assets/pymss_weights}"
      # PortAudio gives the generic PipeWire device and the explicit rvc_output
      # device the same stream identity. Do not let WirePlumber restore one
      # device's previous target when the other one is selected.
      if [ "$mode" = "realtime" ] && [ -z "''${PIPEWIRE_ALSA+x}" ]; then
        export PIPEWIRE_ALSA='{ state.restore-target=false }'
      fi
      export TMPDIR="''${TMPDIR-$cache_dir/tmp}"
      export TMP="''${TMP-$TMPDIR}"
      export TEMP="''${TEMP-$TMPDIR}"
      export TORCH_HOME="''${TORCH_HOME-$cache_dir/torch}"
      export PYTHONPATH="$source_dir:$source_dir/tools''${PYTHONPATH:+:$PYTHONPATH}"

      resolve_data_path() {
        case "$1" in
          /*) realpath --canonicalize-missing -- "$1" ;;
          *) realpath --canonicalize-missing -- "$data_dir/$1" ;;
        esac
      }

      weight_root="$(resolve_data_path "''${weight_root-assets/weights}")"
      weight_pymss_root="$(resolve_data_path "''${weight_pymss_root-assets/pymss_weights}")"
      index_root="$(resolve_data_path "''${index_root-logs}")"
      outside_index_root="$(resolve_data_path "''${outside_index_root-assets/indices}")"
      rmvpe_root="$(resolve_data_path "''${rmvpe_root-assets/rmvpe}")"
      export weight_root weight_pymss_root index_root outside_index_root rmvpe_root
      ${lib.optionalString (acceleration == "cpu") "unset LD_LIBRARY_PATH"}
      ${lib.optionalString (acceleration == "cuda") "export RVC_REQUIRE_CUDA=1"}
      ${lib.optionalString (acceleration == "cuda") ''
        if [ -n "$driver_library_path" ]; then
          export LD_LIBRARY_PATH="$driver_library_path"
        else
          unset LD_LIBRARY_PATH
        fi
      ''}

      cd "$data_dir"

      case "$mode" in
        realtime)
          exec ${pythonEnv}/bin/python "$source_dir/realtime_gui.py" "$@"
          ;;
        web)
          if [ -n "''${RVC_WEBUI_PORT:-}" ]; then
            exec ${pythonEnv}/bin/python "$source_dir/webui.py" \
              --port "$RVC_WEBUI_PORT" "$@"
          fi
          exec ${pythonEnv}/bin/python "$source_dir/webui.py" "$@"
          ;;
        cli)
          exec ${pythonEnv}/bin/python "$source_dir/infer/cli.py" "$@"
          ;;
        pymss)
          exec ${pythonEnv}/bin/python -m tools.pymss.cli "$@"
          ;;
        doctor)
          echo "RVC variant: ${acceleration}"
          echo "RVC source:  $source_dir"
          echo "RVC data:    $data_dir"
          echo "RVC config:  $config_dir"
          ${lib.optionalString (acceleration == "cuda") ''

            echo "Driver libs: $driver_library_path"
          ''}
          echo
          ${pythonEnv}/bin/python ${./scripts/doctor.py} ${acceleration}
          ;;
        *)
          echo "Unknown RVC launcher mode: $mode" >&2
          exit 2
          ;;
      esac
    '';
  };

  mkCommand =
    name: mode:
    pkgs.writeShellScriptBin name ''

      exec ${launcher}/bin/rvc-launcher-${acceleration} ${mode} "$@"
    '';

  realtimeCommand = mkCommand "rvc-realtime" "realtime";

  desktopItem = pkgs.makeDesktopItem {
    name = "rvc-realtime";
    exec = "${realtimeCommand}/bin/rvc-realtime";
    desktopName = "RVC Realtime";
    comment = "Realtime voice conversion GUI";
    categories = [
      "AudioVideo"
      "Audio"
    ];
    terminal = false;
  };

  commands = [
    # The multi-mode launcher itself is shipped so scripts and tests can call
    # it directly (e.g. `rvc-launcher-cuda env`) instead of parsing the
    # generated wrappers.
    launcher
    realtimeCommand
    (mkCommand "rvc-web" "web")
    (mkCommand "rvc-cli" "cli")
    (mkCommand "pymss" "pymss")
    (mkCommand "rvc-doctor" "doctor")
  ];

in
{
  inherit commands desktopItem;
}
