{
  description = "Reproducible CPU/CUDA RVC packages and PipeWire integration";

  # Nix asks once to accept this cache configuration. CI publishes the CPU and
  # CUDA closures here, so accepting it can avoid a large local build.
  nixConfig = {
    extra-substituters = [ "https://ruixi-rebirth.cachix.org" ];
    extra-trusted-public-keys = [
      "ruixi-rebirth.cachix.org-1:ypGqoIU9MfXwv/fE02ZGg8mutJqmcYHgLTR1DMoPGac="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };

    rvc-src = {
      url = "github:RVC-Project/Retrieval-based-Voice-Conversion-WebUI";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      backends = {
        cpu = {
          label = "CPU";
        };
        cuda118 = {
          label = "CUDA 11.8";
        };
        cuda128 = {
          label = "CUDA 12.8";
        };
      };

      # Backend and model assets are independent package dimensions. Public
      # packages, apps, and overlay entries below all select from this table.
      mkRvcPackages =
        pkgs: modelAssets:
        nixpkgs.lib.mapAttrs (
          backend: _spec:
          let
            noModels = pkgs.callPackage ./nix/package.nix {
              inherit inputs;
              acceleration = backend;
              models = null;
            };
          in
          {
            inherit noModels;
            inferenceModels = noModels.override { models = modelAssets.inference; };
            allModels = noModels.override { models = modelAssets.all; };
            pymssModels = noModels.override { models = modelAssets.pymss; };
          }
        ) backends;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      flake = {
        nixosModules.default = import ./nix/module.nix { inherit self; };
        nixosModules.rvc = self.nixosModules.default;

        overlays.default =
          final: _prev:
          let
            modelAssets = final.callPackage ./nix/models.nix { };
            rvcPackages = mkRvcPackages final modelAssets;
          in
          {
            rvc-models-inference = modelAssets.inference;
            rvc-models-pretrained-v1 = modelAssets.pretrained-v1;
            rvc-models-pretrained-v2 = modelAssets.pretrained-v2;
            rvc-models-mute = modelAssets.mute;
            rvc-models-pymss = modelAssets.pymss;
            rvc-models-training = modelAssets.training;
            rvc-models-all = modelAssets.all;

            rvc-cpu = rvcPackages.cpu.inferenceModels;
            rvc-cuda118 = rvcPackages.cuda118.inferenceModels;
            rvc-cuda128 = rvcPackages.cuda128.inferenceModels;
            rvc-cpu-all = rvcPackages.cpu.allModels;
            rvc-cuda118-all = rvcPackages.cuda118.allModels;
            rvc-cuda128-all = rvcPackages.cuda128.allModels;
            rvc = rvcPackages.cpu.inferenceModels;
          };
      };

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        let
          modelAssets = pkgs.callPackage ./nix/models.nix { };
          consumerPkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          rvcPackages = mkRvcPackages pkgs modelAssets;
          treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

          mkApp = pkg: bin: description: {
            type = "app";
            program = "${pkg}/bin/${bin}";
            meta.description = description;
          };

          mkAppsForBackend =
            backend:
            let
              inherit (backends.${backend}) label;
              suffix = if backend == "cpu" then "" else "-${backend}";
              backendPackages = rvcPackages.${backend};
            in
            {
              "realtime${suffix}" =
                mkApp backendPackages.inferenceModels "rvc-realtime"
                  "Start the ${label} RVC realtime GUI";
              "web${suffix}" =
                mkApp backendPackages.inferenceModels "rvc-web"
                  "Start the ${label} RVC WebUI for inference";
              "web-all${suffix}" =
                mkApp backendPackages.allModels "rvc-web"
                  "Start the ${label} RVC WebUI with all model assets";
              "cli${suffix}" =
                mkApp backendPackages.inferenceModels "rvc-cli"
                  "Run ${label} offline RVC inference";
              "pymss${suffix}" =
                mkApp backendPackages.pymssModels "pymss"
                  "Run the ${label} PyMSS CLI with model weights";
            };

          rvcApps = nixpkgs.lib.foldl' (apps: backend: apps // mkAppsForBackend backend) { } (
            builtins.attrNames backends
          );

          generatePatchesCommand = pkgs.writeShellApplication {
            name = "rvc-generate-patches";
            runtimeInputs = [
              pkgs.git
              pkgs.python312
            ];
            text = ''
              repo_root="$PWD"
              if [ ! -f "$repo_root/flake.nix" ] || [ ! -d "$repo_root/nix/patches" ]; then
                echo "run this command from the rvc.nix repository root" >&2
                exit 1
              fi

              exec ${pkgs.python312}/bin/python \
                ${self}/nix/patches/generate_patches.py \
                --repo-root "$repo_root" \
                --src-dir ${inputs.rvc-src} \
                "$@"
            '';
          };
        in
        {
          packages = {
            default = rvcPackages.cpu.inferenceModels;
            cpu = rvcPackages.cpu.inferenceModels;
            cuda118 = rvcPackages.cuda118.inferenceModels;
            cuda128 = rvcPackages.cuda128.inferenceModels;
            cpu-all = rvcPackages.cpu.allModels;
            cuda118-all = rvcPackages.cuda118.allModels;
            cuda128-all = rvcPackages.cuda128.allModels;
            models-inference = modelAssets.inference;
            models-pretrained-v1 = modelAssets.pretrained-v1;
            models-pretrained-v2 = modelAssets.pretrained-v2;
            models-mute = modelAssets.mute;
            models-pymss = modelAssets.pymss;
            models-training = modelAssets.training;
            models-all = modelAssets.all;
          };

          apps = {
            default =
              mkApp rvcPackages.cpu.inferenceModels "rvc-realtime"
                "Start CPU RVC with pinned inference models";
          }
          // rvcApps;

          checks = import ./nix/checks.nix {
            inherit
              consumerPkgs
              inputs
              modelAssets
              pkgs
              self
              treefmtEval
              rvcPackages
              ;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              generatePatchesCommand
              rvcPackages.cpu.noModels
              treefmtEval.config.build.wrapper
              pkgs.uv
              pkgs.python312
            ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON_DOWNLOADS = "never";
            };
          };

          formatter = treefmtEval.config.build.wrapper;
        };
    };
}
