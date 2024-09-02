# https://discourse.nixos.org/t/documentation-for-custom-nixos-options/20320/5
{
  inputs = { };

  outputs =
    { self, ... }:
    let
      lancache = import ./lancache.nix;
    in
    {
      nixosModules.default = lancache;
      nixosModules.lancache = lancache;
      documentation =
        let
          # evaluate our options
          nixpkgs = builtins.getFlake ("github:nixos/nixpkgs/e69fc881bb11a8280c2cdf94c1aaf391ef3e3677");
          lib = nixpkgs.lib;

          eval = nixpkgs.lib.evalModules { modules = [ ./lancache.nix ]; };
          # generate our docs
          optionsDoc = nixpkgs.legacyPackages.x86_64-linux.nixosOptionsDoc { inherit (eval) options; };
        in
        # create a derivation for capturing the markdown output
        nixpkgs.legacyPackages.x86_64-linux.runCommand "options-doc.md" { } ''
          cat ${optionsDoc.optionsCommonMark} >> $out
        '';
    };
}
