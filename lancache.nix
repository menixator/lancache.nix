{ lib, ... }:
with lib.types;
with lib.options;
{

  options = {
    services.lancache = {
      enable = mkEnableOption "lancache";
      upstreamDns = mkOption {
        type = types.listOf types.str;
        description = ''
          The upstream DNS servers the cache should use. The defaults are
          Cloudflare's DNS.

          Corresponds to the environment variable: `UPSTREAM_DNS` in standard
          lancache config.
        '';
        default = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };

      cacheDiskSize = mkOption {
        type = types.str;
        default = "1000g";
        description = ''
          The amount of disk space the container should use for caching data. Specified in gigabytes.

          Corresponds to the environment variable: `CACHE_DISK_SIZE` in
          standard lancache config.
        '';

      };

      cacheIndexSize = mkOption {
        type = types.str;
        default = "500m";
        description = ''
          Amount of index memory for the nginx cache manager. Lancache team
          recommends `250m` of index memory per `1TB` of `cacheDiskSize`

          Corresponds to the environment variable: `CACHE_INDEX_SIZE` in
          standard lancache config.
        '';

      };

      cacheMaxAge = mkOption {
        type = types.str;
        default = "3560d";
        description = ''
          The maximum amount of time a file should be held in cache. There is
          usually no reason to reduce this - the cache will automatically
          remove the oldest content if it needs the space.

          Corresponds to the environment variable: `CACHE_MAX_AGE` in standard
          lancache config.
        '';
      };

      minFreeDisk = mkOption {
        type = types.str;
        default = "10g";
        description = ''
          Sets the minimum free disk space that must be kept at all times. When the
          available free space drops below the set amount for any reason, the cache
          server will begin pruning content to free up space. Specified in gigabytes.

          Corresponds to the environment variable: `CACHE_MAX_AGE` in standard
          lancache config.
        '';
      };

      logFormat = mkOption {
        type = types.enum [
          "cachelog"
          "cachelog-json"
        ];
        default = "cachelog";
        description = ''
          Sets the default logging format

          Nothing corresponds to this option in the standard lancache config
        '';
      };

      cacheLocation = mkOption {
        type = types.str;
        default = null;
        description = ''
          Sets the location to put the cached data in
        '';
      };

      # TODO: might have to create this
      logPrefix = mkOption {
        type = types.str;
        default = null;
        description = ''
          Sets the location to put the cached data in
        '';
      };
    };
  };
}
