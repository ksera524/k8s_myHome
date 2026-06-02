{
  description = "k8s_myHome local operator and validation toolchains";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        validateTools = with pkgs; [
          bash
          coreutils
          findutils
          git
          gnugrep
          gnused
          gawk
          jq
          kubeconform
          kustomize
          kubectl
          kubernetes-helm
          openssh
          python3
          python3Packages.pyyaml
          shellcheck
          yamllint
        ];
        bootstrapTools = validateTools ++ (with pkgs; [
          ansible
          curl
          openssl
          rsync
          terraform
          unzip
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          packages = validateTools;
          shellHook = ''
            echo "validate: automation/scripts/ci/validate.sh"
          '';
        };

        devShells.bootstrap = pkgs.mkShell {
          packages = bootstrapTools;
          shellHook = ''
            export K8S_MYHOME_USE_NIX_TOOLCHAIN=true
            echo "bootstrap: make phase1 -> make phase2 -> make bootstrap -> make phase5"
          '';
        };
      });
}
