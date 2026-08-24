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
      # Single source of truth for every RVC package variant. The perSystem
      # outputs and the default overlay both build from this table, so a new
      # variant is immediately available as a package, an app, and an overlay
      # attribute; the overlay-interface check only verifies the wiring.
      # Model variants reuse the lean package's callPackage fixpoint via
      # override, mirroring how consumers would customise the overlay.
      mkVariants =
        pkgs: modelSets:
        let
          mkPackage =
            acceleration: models:
            pkgs.callPackage ./nix/package.nix {
              inherit inputs acceleration models;
            };
          cpu = mkPackage "cpu" null;
          cuda = mkPackage "cuda" null;
        in
        {
          cpu = cpu;
          cpu-with-models = cpu.override { models = modelSets.inference; };
          cpu-with-all-models = cpu.override { models = modelSets.all; };
          cuda = cuda;
          cuda-with-models = cuda.override { models = modelSets.inference; };
          cuda-with-all-models = cuda.override { models = modelSets.all; };
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      flake = {
        nixosModules.default = import ./nix/module.nix { inherit self; };
        nixosModules.rvc = self.nixosModules.default;

        overlays.default =
          final: _prev:
          let
            modelSets = final.callPackage ./nix/models.nix { };
            variants = mkVariants final modelSets;
          in
          {
            rvc-models-inference = modelSets.inference;
            rvc-models-training = modelSets.training;
            rvc-models-all = modelSets.all;

            rvc-cpu = variants.cpu;
            rvc-cuda = variants.cuda;
            rvc-cpu-with-models = variants.cpu-with-models;
            rvc-cuda-with-models = variants.cuda-with-models;
            rvc-cpu-with-all-models = variants.cpu-with-all-models;
            rvc-cuda-with-all-models = variants.cuda-with-all-models;
            rvc = variants.cpu;
          };
      };

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        let
          modelSets = pkgs.callPackage ./nix/models.nix { };
          consumerPkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          variants = mkVariants pkgs modelSets;
          treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

          mkApp = pkg: bin: description: {
            type = "app";
            program = "${pkg}/bin/${bin}";
            meta.description = description;
          };

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
          packages = variants // {
            default = variants.cpu;
            models-inference = modelSets.inference;
            models-pretrained-v1 = modelSets.pretrained-v1;
            models-pretrained-v2 = modelSets.pretrained-v2;
            models-mute = modelSets.mute;
            models-training = modelSets.training;
            models-all = modelSets.all;
          };

          apps = {
            default =
              mkApp variants.cpu-with-models "rvc-realtime"
                "Start CPU RVC with pinned inference models";
            realtime = mkApp variants.cpu "rvc-realtime" "Start the CPU RVC realtime GUI";
            web = mkApp variants.cpu "rvc-web" "Start the CPU RVC training and inference WebUI";
            cli = mkApp variants.cpu "rvc-cli" "Run CPU offline RVC inference from the command line";
            pymss = mkApp variants.cpu "pymss" "Run the CPU PyMSS command-line interface";
            with-models =
              mkApp variants.cpu-with-models "rvc-realtime"
                "Start CPU RVC with pinned inference models";
            web-with-models =
              mkApp variants.cpu-with-models "rvc-web"
                "Start CPU RVC WebUI with pinned inference models";
            web-with-all-models =
              mkApp variants.cpu-with-all-models "rvc-web"
                "Start CPU RVC WebUI with all pinned model assets";
            cli-with-models =
              mkApp variants.cpu-with-models "rvc-cli"
                "Run CPU RVC CLI with pinned inference models";
            cuda = mkApp variants.cuda "rvc-realtime" "Start the CUDA RVC realtime GUI";
            cuda-web = mkApp variants.cuda "rvc-web" "Start the CUDA RVC WebUI";
            cuda-cli = mkApp variants.cuda "rvc-cli" "Run CUDA offline RVC inference from the command line";
            cuda-pymss = mkApp variants.cuda "pymss" "Run the CUDA PyMSS command-line interface";
            generate-patches =
              mkApp generatePatchesCommand "rvc-generate-patches"
                "Regenerate downstream patches from the locked upstream source";
            cuda-with-models =
              mkApp variants.cuda-with-models "rvc-realtime"
                "Start CUDA RVC with pinned inference models";
            cuda-web-with-models =
              mkApp variants.cuda-with-models "rvc-web"
                "Start CUDA RVC WebUI with pinned inference models";
            cuda-web-with-all-models =
              mkApp variants.cuda-with-all-models "rvc-web"
                "Start CUDA RVC WebUI with all pinned model assets";
            cuda-cli-with-models =
              mkApp variants.cuda-with-models "rvc-cli"
                "Run CUDA RVC CLI with pinned inference models";
          };

          checks = import ./nix/checks.nix {
            inherit
              consumerPkgs
              inputs
              modelSets
              pkgs
              self
              treefmtEval
              variants
              ;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              variants.cpu
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
