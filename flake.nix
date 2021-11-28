{
  description = "frtrader flake";

  inputs = {
    nixpkgs.url = "nixpkgs/21.05";
    flake-utils.url = github:numtide/flake-utils;
    coinbene-api = {
      url = github:dimitri-xyz/coinbene-api ;
      flake = false;
    };
    coinbene-connector = {
      url = github:dimitri-xyz/coinbene-connector ;
      flake = false;
    };
    market-interface = {
      url = github:dimitri-xyz/market-interface ;
      flake = false;
    };
    market-model = {
      url = github:dimitri-xyz/market-model ;
      flake = false;
    };
    razao-base = {
      url = github:dimitri-xyz/razao-base;
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs { inherit system; };
    in {
      devShell = import ./shell.nix {
        inherit pkgs;
        srcPaths = {
          inherit (inputs)
            coinbene-api
            coinbene-connector
            market-interface
            market-model
            razao-base;
        };
      };
    });
}
