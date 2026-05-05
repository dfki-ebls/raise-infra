{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
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
      url = "github:mirkolenz/llmhop/v1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        flocken.follows = "flocken";
        treefmt-nix.follows = "treefmt-nix";
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
