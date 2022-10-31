{ pkgs, lib, haskell-nix, ghc-names ? __attrNames pkgs.haskell.compiler }:

let

  inherit (builtins) toJSON listToAttrs; # fromJSON readFile toFile;

  inherit (lib) attrNames mapAttrs elem filterAttrs; #hasAttr attrValues;

  inherit (pkgs) writeText;

  inherit (haskell-nix) stackage hackage;

  blacklist = ["lts-19.18"];

  get-ghc-nix-name = n: (stackage.${n} hackage).compiler.nix-name;

  is-ghc-compat = n: elem (get-ghc-nix-name n) ghc-names;

  stackage' = filterAttrs (n: _: ! elem n blacklist && is-ghc-compat n) stackage;

  snapshots = mapAttrs (n: _: haskell-nix.snapshots.${n}) stackage';

  resolvers = attrNames snapshots;

  resolvers-json = writeText "resolvers.json" (toJSON resolvers);

  pkg-identifiers-json = let
    pred = n: p: ! elem n ["ghc"]
                 && p ? identifier
                 && (__tryEval p.identifier.name).success
                 && (__tryEval p.identifier.version).success;
    func = ps: mapAttrs (_: v: v.identifier) (filterAttrs pred ps);
  in
    listToAttrs (
      map
        (resolver:
          {
            name = resolver;
            value = writeText
              "${resolver}-pkg-identifiers.json"
              (toJSON (func haskell-nix.snapshots.${resolver}));
          })
        resolvers);

in

{
  inherit get-ghc-nix-name resolvers-json pkg-identifiers-json;
}
