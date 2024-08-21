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
    };
}
