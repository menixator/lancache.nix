{
  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    (flake-utils.lib.eachDefaultSystem (system: {

      # builtins.storePath
      # https://www.nmattia.com/posts/2019-10-08-runtime-dependencies/
      # https://github.com/NixOS/nix/issues/1245#issuecomment-401642781
      #nixosConfigurations.myNixosConfig.options.environment.systemPackages.definitionsWithLocation
      # a=(builtins.getFlake "git+file:///home/menixator/projects/lancache-nix")

      getInputDrvs =
        { pkg, lib }:
        let
          drv = builtins.readFile pkg.drvPath;
          storeDirRe = lib.replaceStrings [ "." ] [ "\\." ] builtins.storeDir;
          storeBaseRe = "[0-9a-df-np-sv-z]{32}-[+_?=a-zA-Z0-9-][+_?=.a-zA-Z0-9-]*";
          re = "(${storeDirRe}/${storeBaseRe}\\.drv)";
          inputs = (lib.concatLists (lib.filter lib.isList (builtins.split re drv)));
        in
        map import inputs;

      nginx-conf =
        let
          inputDrvs = getInputDrvs {
            pkg = self.nixosConfigurations.x86_64-linux.stub.config.systemd.units."nginx.service".unit;
            inherit lib;
          };
          nginx-conf = lib.lists.findFirst (
            drv: (builtins.parseDrvName drv.name).name == "nginx.conf"
          ) null inputDrvs;
        in
        nginx-conf;
    }))
    // (
      let
        lancache = import ./lancache.nix;
      in
      {
        nixosModules.default = lancache;
        nixosModules.lancache = lancache;
      }
    );
}
