{ pkgs, lib, haskell-nix, ghc-names ? __attrNames pkgs.haskell.compiler }:

let

  inherit (builtins) toJSON fromJSON readFile toFile listToAttrs;

  inherit (lib) filterAttrs mapAttrs hasAttr elem attrNames attrValues;

  inherit (pkgs) writeText;

  inherit (haskell-nix) stackage hackage;

  json-cached = json-cached' "cached";

  json-cached' = file-name:
    x: fromJSON (readFile (writeText file-name (toJSON x)));

  json-cached-attrs = identifiers:
    mapAttrs (name: value: json-cached' "${name}.json" value) identifiers;

  blacklist = ["lts-19.18"];

  get-ghc-nix-name = n: (stackage.${n} hackage).compiler.nix-name;

  is-ghc-compat = n: elem (get-ghc-nix-name n) ghc-names;

  stackage' = filterAttrs (n: _: ! elem n blacklist && is-ghc-compat n) stackage;

  snapshots = mapAttrs (n: _: haskell-nix.snapshots.${n}) stackage';

  resolvers-json = writeText "resolvers.json" (toJSON (attrNames snapshots));

  resolvers = fromJSON (readFile ./resolvers.json);

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

  pkg-identifiers = let
    pred = n: p: ! elem n ["ghc"]
                 && p ? identifier
                 && (__tryEval p.identifier.name).success
                 && (__tryEval p.identifier.version).success;
    func = ps: mapAttrs (_: v: v.identifier) (filterAttrs pred ps);
    result = mapAttrs (_: ps: func ps) snapshots;
  in json-cached-attrs result;

  inherit (import ./callHackage-with-system-lib.nix
    {
      inherit lib;
      inherit (pkgs.haskellPackages) callHackage;
    }) callHackageWithSysDeps-expr callHackageWithSysDeps;

  overlays = { hself, pkgs }:
    let
      mkHpkg = callHackageWithSysDeps { inherit hself pkgs; };
      mkOverlay = identifiers:
        mapAttrs ({name, version}: mkHpkg name version {}) identifiers;
    in mapAttrs (_: ids: mkOverlay ids) pkg-identifiers;

  overlays-nix = let
    mk-nix-exprs = identifiers:
      attrValues (
        mapAttrs
          (nix-name: {name, version}:
            ''"${nix-name}" = ${callHackageWithSysDeps-expr name version}'')
          identifiers);
  in
    mapAttrs
      (resolver: identifiers:
        pkgs.writeText "haskell-overlay-${resolver}.nix" ''
    { pkgs }:
    hself: hsuper: {

            ${lib.concatStringsSep "\n\n  " (mk-nix-exprs identifiers)}

    }
    '') pkg-identifiers;

  overlay =
    self: super:
    {
      stackage =
        (super.stackage or {}) //
        mapAttrs
          (resolver: identifiers:
            let haskell-overlay =
                  hself: hsuper:
                  (overlays { inherit hself pkgs; }).${resolver} hself hsuper;
                ghc-nix-name = get-ghc-nix-name resolver;
            in self.haskell.packages.${ghc-nix-name}.extend haskell-overlay)
          pkg-identifiers;
    };
in {

  inherit get-ghc-nix-name pkg-identifiers pkg-identifiers-json;
  inherit resolvers resolvers-json snapshots stackage';
  inherit overlay overlays overlays-nix;

}
