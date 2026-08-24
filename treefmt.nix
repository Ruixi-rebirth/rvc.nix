{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true;
    shellcheck.enable = true;
    shfmt.enable = true;
    taplo.enable = true;
  };

  # Disable schema catalogs so TOML lint remains deterministic and offline.
  settings.formatter.taplo-lint = {
    command = pkgs.taplo;
    options = [
      "lint"
      "--no-schema"
    ];
    includes = [ "*.toml" ];
  };

  # markdownlint is intentionally check-only: unlike a Markdown formatter, it
  # will not reflow Chinese prose or rewrite tables.
  settings.formatter.markdownlint = {
    command = pkgs.markdownlint-cli2;
    includes = [ "*.md" ];
  };
}
