{
  description = "frtrader flake";

  inputs = {
    nixpkgs.url = "nixpkgs/21.05";
    flake-utils.url = github:numtide/flake-utils;
    coinbene-api = {
      url = github:dimitri-xyz/coinbene-api/899b6d0f1c4c4b7adfb90325f1ff8ecf86953c08;
      flake = false;
    };
    coinbene-connector = {
      url = github:dimitri-xyz/coinbene-connector/6591768e221696bbe3c6d635c87f8f391c0afe54;
      flake = false;
    };
    market-interface = {
      url = github:dimitri-xyz/market-interface/408943c819f21bb6a97f99e95b987431bee7f806;
      flake = false;
    };
    market-model = {
      url = github:dimitri-xyz/market-model/ab1674058ee39e556a7fcade4de260ff1bdb503a;
      flake = false;
    };
    razao-base = {
      url = github:dimitri-xyz/razao-base/5fc12c80aab9757f3aa1202d1abd4a7e172922df;
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
