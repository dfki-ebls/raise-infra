{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    nixpkgs-stable.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
    systems.url = "github:nix-systems/default";
    determinate.url = "github:determinatesystems/determinate";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flocken = {
      url = "github:mirkolenz/flocken/v2";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
    llmhop = {
      url = "github:mirkolenz/llmhop/v2";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        flocken.follows = "flocken";
        treefmt-nix.follows = "treefmt-nix";
        quadlet-nix.follows = "quadlet-nix";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        pyproject-build-systems.follows = "pyproject-build-systems";
      };
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
      };
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };
    quadlet-nix = {
      url = "github:mirkolenz/quadlet-nix/v1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ragold = {
      url = "github:dfki-ebls/ragold";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
    hivegent = {
      url = "github:dfki-ebls/hivegent";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
        flocken.follows = "flocken";
      };
    };
    website = {
      url = "github:dfki-ebls/raise-website";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
  };
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake {
      inherit inputs;
      specialArgs = {
        lib'.flocken = inputs.flocken.lib;
      };
    } ./flake;
}
