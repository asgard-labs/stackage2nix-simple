{ lib, callHackage }:

let

  extract-inputs = drv:
    let
      deriver = import drv.passthru.cabal2nixDeriver;
      fun-args = __functionArgs deriver;
      args-for-extraction =
        (__mapAttrs (n: _: n) fun-args)
        // { mkDerivation = x: builtins.removeAttrs x [ "lib" ]; };
      drv-info = deriver args-for-extraction;
    in {
      inherit (drv-info) pname version;
      librarySystemDepends = drv-info.librarySystemDepends or [];
    };

  get-sysdep-names = drv: (extract-inputs drv).librarySystemDepends;

  get-sysdep-args = pkgs: drv:
    let
      sysdep-names = get-sysdep-names drv;
    in __listToAttrs (
      builtins.map
        (n: { name = n; value = pkgs.${n}; })
        sysdep-names);

  callHackageWithSysDeps-expr = callHackageWithSysDeps-expr' "hself";

  callHackageWithSysDeps-expr' = hself-name:
    pname: version: let

      drv = callHackage pname version {};

      sysdep-names = get-sysdep-names drv;

      sysdep-bindings =
        let
          f = name: ''"${name}" = pkgs."${name}";'';
        in builtins.map f sysdep-names;

    in ''"${hself-name}".callHackage "${pname}" "${version}" { ${lib.concatStringsSep " " sysdep-bindings} };'';

  callHackageWithSysDeps = { hself, pkgs }:
    pname: version: args: let

      get-drv = hself.callHackage pname version;

      drv = get-drv {};

      sysdep-args = get-sysdep-args pkgs drv;

    in get-drv (sysdep-args // args);

in

{

  inherit get-sysdep-names extract-inputs get-sysdep-args;

  inherit callHackageWithSysDeps callHackageWithSysDeps-expr;

}
