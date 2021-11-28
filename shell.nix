{
  pkgs ? import <nixpkgs> {},
  srcPaths ? {
    coinbene-api = builtins.fetchGit https://github.com/dimitri-xyz/coinbene-api ;
    coinbene-connector = builtins.fetchGit https://github.com/dimitri-xyz/coinbene-connector ;
    market-interface = builtins.fetchGit https://github.com/dimitri-xyz/market-interface ;
    market-model = builtins.fetchGit https://github.com/dimitri-xyz/market-model ;
    razao-base = builtins.fetchGit https://github.com/dimitri-xyz/razao-base;
  }
}:

with pkgs;

let

  myHask0 = haskellPackages.extend (haskell.lib.packageSourceOverrides {
    FRTrader = ./.;
    inherit (srcPaths)
      coinbene-api
      coinbene-connector
      market-interface
      market-model
      razao-base ;
  });

  myHask1 = myHask0.extend (hself: hsuper: {
    trading-strategy = null;
    reactive-banana = hself.callHackageDirect {
      pkg = "reactive-banana";
      ver =  "1.2.2.0";
      sha256 = "uhm6YJ/+YG7unKfrrBThDiPDgF3wuPcOvPql9nURQ2w=";
    } {};
    coinbene-api = haskell.lib.dontCheck hsuper.coinbene-api;
    coinbene-connector = haskell.lib.dontCheck hsuper.coinbene-connector;
  });

in myHask1.shellFor {
  packages = (p: with p; [
    FRTrader
    # coinbene-connector
    # market-model
    # razao-base
    # reactive-banana
    # coinbene-api
    # market-interface
  ]);
  buildInputs = with myHask1; [ ghcid haskell-language-server ];
}
