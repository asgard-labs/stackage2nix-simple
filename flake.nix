{

  inputs.nixpkgs.url = github:nixos/nixpkgs;
  inputs.haskell-nix.url = github:input-output-hk/haskell.nix;

  outputs = { self, ... }@inputs: let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.haskell-nix.overlay ];
    };
  in

    {

    aux-nix-generator = import ./aux-nix-generator.nix {
      inherit pkgs;
      inherit (inputs) haskell-nix;
      inherit (pkgs) lib;
    };

    stackage = let
      inherit (self.aux-nix-generator) get-ghc-nix-name;
      in pkgs.callPackage ./stackage2nix-simple.nix {
        inherit pkgs get-ghc-nix-name;
        inherit (pkgs) lib;};

    apps.${system}.default = let
      inherit (builtins) fromJSON readFile;
      inherit (pkgs) lib;
      inherit (self.aux-nix-generator) pkg-identifiers-json resolvers-json;
      resolvers = fromJSON (readFile resolvers-json);
      script-bin = pkgs.writeScriptBin "update-nix-files.sh" ''

        set -x

        cp -f -L ${resolvers-json} ./resolvers.json
        mkdir -p ./pkg-identifiers

        ${lib.concatStringsSep "\n" (map (n: ''
          nix build .#stackage.pkg-identifiers-json.\"${n}\"
          cp -f -L ./result ./pkg-identifiers/${n}.json

        rm ./result

        '') resolvers)}
      '';
    in {
      type = "app";
      program = "${script-bin}/bin/update-nix-files.sh";
    };

    # packages.${system}.default =
    #   # pkgs.linkFarmFromDrvs "pkg-identifiers" (__attrValues self.stackage.pkg-identifiers-json);
    #   pkgs.linkFarmFromDrvs "pkg-identifiers" [self.stackage.pkg-identifiers."lts-19.3"];

    # inherit (pkgs) lib;

  };

}
