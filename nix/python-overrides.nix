{ pkgs, python }:

final: prev:
let
  cudaSuffix =
    if builtins.hasAttr "nvidia-cublas-cu11" final then
      "cu11"
    else if builtins.hasAttr "nvidia-cublas-cu12" final then
      "cu12"
    else
      null;

  cudaLibraries = {
    nvidia-cublas = "cublas";
    nvidia-cuda-cupti = "cuda_cupti";
    nvidia-cuda-nvrtc = "cuda_nvrtc";
    nvidia-cuda-runtime = "cuda_runtime";
    nvidia-cudnn = "cudnn";
    nvidia-cufft = "cufft";
    nvidia-cufile = "cufile";
    nvidia-curand = "curand";
    nvidia-cusolver = "cusolver";
    nvidia-cusparse = "cusparse";
    nvidia-cusparselt = "cusparselt";
    nvidia-nccl = "nccl";
    nvidia-nvjitlink = "nvjitlink";
    nvidia-nvtx = "nvtx";
  };
  availableCudaLibraries = pkgs.lib.filterAttrs (
    base: _directory: cudaSuffix != null && builtins.hasAttr "${base}-${cudaSuffix}" final
  ) cudaLibraries;
  cudaLibraryPath =
    base: directory:
    if base == "nvidia-cusparselt" then "cusparselt/lib" else "nvidia/${directory}/lib";
  cudaPackages = pkgs.lib.mapAttrsToList (
    base: _directory: final.${"${base}-${cudaSuffix}"}
  ) availableCudaLibraries;
  cudaSearchPaths = pkgs.lib.concatStringsSep "\n" (
    pkgs.lib.mapAttrsToList (
      base: directory:
      "addAutoPatchelfSearchPath ${
        final.${"${base}-${cudaSuffix}"}
      }/${python.sitePackages}/${cudaLibraryPath base directory}"
    ) availableCudaLibraries
  );
  nvrtcPackage = final.${"nvidia-cuda-nvrtc-${cudaSuffix}"};

  fixCusolver =
    suffix:
    let
      cublas = final.${"nvidia-cublas-${suffix}"};
      cuda12Dependencies = pkgs.lib.optionals (suffix == "cu12") [
        final.nvidia-cusparse-cu12
        final.nvidia-nvjitlink-cu12
      ];
    in
    prev.${"nvidia-cusolver-${suffix}"}.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ cublas ] ++ cuda12Dependencies;
      preFixup = (old.preFixup or "") + ''
        addAutoPatchelfSearchPath ${cublas}/${python.sitePackages}/nvidia/cublas/lib
        ${pkgs.lib.optionalString (suffix == "cu12") ''
          addAutoPatchelfSearchPath ${final.nvidia-cusparse-cu12}/${python.sitePackages}/nvidia/cusparse/lib
          addAutoPatchelfSearchPath ${final.nvidia-nvjitlink-cu12}/${python.sitePackages}/nvidia/nvjitlink/lib
        ''}
      '';
    });

  fixCudnn =
    suffix:
    let
      cublas = final.${"nvidia-cublas-${suffix}"};
    in
    prev.${"nvidia-cudnn-${suffix}"}.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ cublas ];
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
      preFixup = (old.preFixup or "") + ''
        addAutoPatchelfSearchPath ${cublas}/${python.sitePackages}/nvidia/cublas/lib
      '';
      # cuDNN opens its split graph/ops/engine libraries with dlopen. They live
      # beside libcudnn itself and therefore are invisible to DT_NEEDED-based
      # autoPatchelf discovery unless the wheel's own directory remains in
      # RUNPATH. A postFixup string runs before autoPatchelfPostFixup, so use a
      # separate post phase that runs after every fixup hook instead.
      postPhases = (old.postPhases or [ ]) ++ [ "addCudnnOriginRpathPhase" ];
      addCudnnOriginRpathPhase = ''
        found_library=
        for library in "$out/${python.sitePackages}/nvidia/cudnn/lib/"libcudnn*.so.9; do
          if [[ ! -e "$library" ]]; then
            continue
          fi

          found_library=1
          patchelf --add-rpath '$ORIGIN' "$library"

          rpath="$(patchelf --print-rpath "$library")"
          case ":$rpath:" in
            *:'$ORIGIN':*) ;;
            *)
              echo "cuDNN library is missing a wheel-local RPATH: $library ($rpath)" >&2
              exit 1
              ;;
          esac
        done

        if [[ -z "$found_library" ]]; then
          echo "no cuDNN shared libraries found in the installed wheel" >&2
          exit 1
        fi
      '';
    });
in
{
  nvidia-cusolver-cu11 = fixCusolver "cu11";
  nvidia-cusolver-cu12 = fixCusolver "cu12";
  nvidia-cudnn-cu11 = fixCudnn "cu11";
  nvidia-cudnn-cu12 = fixCudnn "cu12";

  # CUDA 12 wheels include a GPUDirect Storage RDMA plugin. Keep its verbs
  # libraries scoped to cuFile; ordinary RVC execution does not need them in
  # the launcher's global library path.
  nvidia-cufile-cu12 = prev.nvidia-cufile-cu12.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.rdma-core ];
  });

  nvidia-cusparse-cu12 = prev.nvidia-cusparse-cu12.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ final.nvidia-nvjitlink-cu12 ];
    preFixup = (old.preFixup or "") + ''
      addAutoPatchelfSearchPath ${final.nvidia-nvjitlink-cu12}/${python.sitePackages}/nvidia/nvjitlink/lib
    '';
  });

  # The Python extension loads libonnxruntime_providers_shared.so from its own
  # capi directory. Preserve that wheel-local lookup without adding the whole
  # Python environment to the launcher's global library path.
  onnxruntime = prev.onnxruntime.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
    postPhases = (old.postPhases or [ ]) ++ [ "addOnnxruntimeOriginRpathPhase" ];
    addOnnxruntimeOriginRpathPhase = ''
      found_extension=
      for extension in \
        "$out/${python.sitePackages}/onnxruntime/capi/"onnxruntime_pybind11_state*.so
      do
        if [[ ! -e "$extension" ]]; then
          continue
        fi

        found_extension=1
        patchelf --add-rpath '$ORIGIN' "$extension"

        rpath="$(patchelf --print-rpath "$extension")"
        case ":$rpath:" in
          *:'$ORIGIN':*) ;;
          *)
            echo "ONNX Runtime extension is missing a wheel-local RPATH: $extension ($rpath)" >&2
            exit 1
            ;;
        esac
      done

      if [[ -z "$found_extension" ]]; then
        echo "ONNX Runtime extension not found in the installed wheel" >&2
        exit 1
      fi
    '';
  });

  "onnxruntime-gpu" = prev."onnxruntime-gpu".overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ cudaPackages;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
    preFixup = (old.preFixup or "") + ''
      ${cudaSearchPaths}
    '';
    # libcuda comes from the host driver. The wheel also ships an optional
    # TensorRT provider, while RVC uses its CUDA provider and does not depend on
    # TensorRT itself.
    autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [
      "libcuda.so.1"
      "libnvinfer.so.10"
      "libnvinfer_plugin.so.10"
      "libnvonnxparser.so.10"
    ];
    postPhases = (old.postPhases or [ ]) ++ [ "addOnnxruntimeGpuOriginRpathPhase" ];
    addOnnxruntimeGpuOriginRpathPhase = ''
      found_extension=
      for extension in \
        "$out/${python.sitePackages}/onnxruntime/capi/"onnxruntime_pybind11_state*.so
      do
        if [[ ! -e "$extension" ]]; then
          continue
        fi

        found_extension=1
        patchelf --add-rpath '$ORIGIN' "$extension"
      done

      if [[ -z "$found_extension" ]]; then
        echo "ONNX Runtime GPU extension not found in the installed wheel" >&2
        exit 1
      fi
    '';
  });

  torch = prev.torch.overrideAttrs (
    old:
    pkgs.lib.optionalAttrs (cudaSuffix != null) {
      buildInputs = (old.buildInputs or [ ]) ++ cudaPackages;
      preFixup = (old.preFixup or "") + ''
        ${cudaSearchPaths}
      '';
      # libcuda is supplied by the host NVIDIA driver through
      # /run/opengl-driver/lib, not by the redistributable CUDA wheels.
      autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [ "libcuda.so.1" ];
      # libtorch_cuda dlopens libnvrtc instead of declaring it in DT_NEEDED,
      # so autoPatchelf never adds the nvrtc directory to any RUNPATH and
      # torch.cuda.nvrtc fails at runtime. Add the directory to every torch
      # library that references libnvrtc, mirroring nixpkgs torch-bin.
      postPhases = (old.postPhases or [ ]) ++ [ "addNvrtcRpathPhase" ];
      addNvrtcRpathPhase = ''
        found_nvrtc=
        for library in "$out/${python.sitePackages}/torch/lib/"*.so*; do
          [[ -e "$library" ]] || continue
          if ! grep -aq 'libnvrtc' "$library"; then
            continue
          fi

          found_nvrtc=1
          patchelf --add-rpath \
            '${nvrtcPackage}/${python.sitePackages}/nvidia/cuda_nvrtc/lib' \
            "$library"
        done

        if [[ -z "$found_nvrtc" ]]; then
          echo "no torch library references libnvrtc" >&2
          exit 1
        fi
      '';
    }
  );

  # websockets 10.4 predates PEP 517 adoption and its sdist has no
  # pyproject.toml.  Declare the implicit legacy setuptools backend instead of
  # leaking setuptools into every package in the environment.
  websockets = prev.websockets.overrideAttrs (old: {
    nativeBuildInputs =
      (old.nativeBuildInputs or [ ])
      ++ final.resolveBuildSystem {
        setuptools = [ ];
      };
  });

  # The PyTorch wheels declare these relationships as Python dependencies, but
  # their extension modules also link directly against libtorch*.so. Expose the
  # torch output to autoPatchelf while keeping it out of unrelated wheels.
  torchaudio = prev.torchaudio.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [
      final.torch
      pkgs.ffmpeg_6
      pkgs.sox
    ];
    postInstall = (old.postInstall or "") + ''
      torio_lib_dir="$out/${python.sitePackages}/torio/lib"

      rm -- \
        "$torio_lib_dir/libtorio_ffmpeg4.so" \
        "$torio_lib_dir/_torio_ffmpeg4.so" \
        "$torio_lib_dir/libtorio_ffmpeg5.so" \
        "$torio_lib_dir/_torio_ffmpeg5.so"

      test -f "$torio_lib_dir/libtorio_ffmpeg6.so"
      test -f "$torio_lib_dir/_torio_ffmpeg6.so"
    '';
    preFixup = (old.preFixup or "") + ''
      addAutoPatchelfSearchPath ${final.torch}/${python.sitePackages}/torch/lib
    '';
  });

  torchvision = prev.torchvision.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ final.torch ];
    preFixup = (old.preFixup or "") + ''
      addAutoPatchelfSearchPath ${final.torch}/${python.sitePackages}/torch/lib
    '';
  });

  numba = prev.numba.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.tbb ];
  });

  sounddevice = prev.sounddevice.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.portaudio ];
    postInstall = (old.postInstall or "") + ''
      substituteInPlace "$out/${python.sitePackages}/sounddevice.py" \
        --replace-fail \
          "'portaudio',  # Default name on POSIX systems" \
          "'${pkgs.portaudio}/lib/libportaudio.so',  # Nix store path" \
        --replace-fail \
          '_libname = _find_library(_libname)' \
          '_libname = _libname if _os.path.isabs(_libname) else _find_library(_libname)'
    '';
  });

  soundfile = prev.soundfile.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libsndfile ];
    postInstall = (old.postInstall or "") + ''
      soundfile_py="$out/${python.sitePackages}/soundfile.py"
      primary_lookup="_libname = _find_library('sndfile')"
      fallback_lookup="_explicit_libname = 'libsndfile.so'"
      nix_lookup="${pkgs.lib.getLib pkgs.libsndfile}/lib/libsndfile.so"

      if [[ "$(grep -Fc "$primary_lookup" "$soundfile_py")" -ne 1 ]]; then
        echo "expected exactly one soundfile primary library lookup" >&2
        exit 1
      fi
      if [[ "$(grep -Fc "$fallback_lookup" "$soundfile_py")" -ne 1 ]]; then
        echo "expected exactly one soundfile fallback library lookup" >&2
        exit 1
      fi

      substituteInPlace "$soundfile_py" \
        --replace-fail \
          "$primary_lookup" \
          "_libname = '$nix_lookup'" \
        --replace-fail \
          "$fallback_lookup" \
          "_explicit_libname = '$nix_lookup'"

      if [[ "$(grep -Fc "$nix_lookup" "$soundfile_py")" -ne 2 ]]; then
        echo "soundfile did not receive both absolute libsndfile paths" >&2
        exit 1
      fi
      if grep -Fq "$primary_lookup" "$soundfile_py" || grep -Fq "$fallback_lookup" "$soundfile_py"; then
        echo "soundfile retained an unpatched libsndfile lookup" >&2
        exit 1
      fi
    '';
  });
}
