{ pkgs, lib, get-ghc-nix-name }:

let

  inherit (builtins) toJSON fromJSON readFile toFile listToAttrs;

  inherit (lib) filterAttrs mapAttrs hasAttr elem attrNames attrValues;

  inherit (pkgs) writeText;

  resolvers = fromJSON (readFile ./resolvers.json);

  pkg-identifiers = listToAttrs (
    map
      (resolver:
        {
          name = resolver;
          value = fromJSON (readFile (./. + "/pkg-identifiers/${resolver}.json"));
        })
      resolvers);

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
in

{

  inherit get-ghc-nix-name pkg-identifiers;
  inherit resolvers;
  inherit overlay overlays overlays-nix;

}
