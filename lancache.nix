{
  lib,
  pkgs,
  config,
  ...
}:
with lib.types;
with lib.options;
{

  options = {
    services.lancache = {
      enable = mkEnableOption "lancache";
      upstreamDns =
        mkOption {
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
        }
        // {
          apply = (lib.concatStringsSep " ");
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

      sliceSize = mkOption {
        type = types.str;
        default = "1m";
        description = ''
          See the guide before changing this. It WILL invalidate any currently cached data.

          link: https://lancache.net/docs/advanced/tuning-cache/#b---tweaking-slice-size

          Corresponds to the environment variable: `CACHE_SLICE_SIZE` in standard
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

      domainsPackage = mkOption {
        type = types.package;
        default = pkgs.fetchFromGitHub {
          owner = "uklans";
          repo = "cache-domains";
          rev = "1f5897f4dacf3dab5f4d6fca2fe497d3327eaea9";
          sha256 = "sha256-xrHuYIrGSzsPtqErREMZ8geawvtYcW6h2GyeGMw1I88=";
        };
      };

      domainIndex = lib.mkOption {
        type = lib.types.listOf types.attrs;
        visible = false;
        readOnly = true;
        description = "Parsed domains list";
      };

      workerProcesses =
        lib.mkOption {
          type = lib.types.oneOf [
            (types.enum [ "auto" ])
            (types.ints.u32)
          ];
          description = "Defines the number of worker processes.";
          default = "auto";
        }
        // {
          apply = (builtins.toString);
        };

    };
  };

  config =
    let
      cfg = config.services.lancache;

      isNonEmpty = (
        domain:
        (builtins.replaceStrings
          [
            " "
            "\t"
          ]
          [
            ""
            ""
          ]
          domain
        ) != ""
        && ((builtins.substring 0 1 domain) != "#")
      );

      convertIntoRegex = (
        builtins.replaceStrings
          [
            "."
            "*"
          ]
          [
            "\\."
            "\\*"
          ]
      );

      fetchAndTransformHosts =
        file:
        lib.pipe file [
          builtins.readFile
          (lib.splitString "\n")
          (builtins.filter isNonEmpty)
          (map convertIntoRegex)
        ];

      index = lib.pipe (cfg.domainsPackage + "/cache_domains.json") [
        builtins.readFile
        builtins.fromJSON
        (x: x.cache_domains)
        (map (
          entry:
          entry
          // {
            domains = lib.pipe entry.domain_files [
              (map (fileName: (cfg.domainsPackage + "/" + fileName)))
              (map fetchAndTransformHosts)
              (lib.flatten)
            ];
          }
        ))
      ];

      mapEntries = lib.pipe index [
        (map (
          entry:
          map (host: {
            cacheKey = entry.name;
            inherit host;
          }) entry.domains
        ))
        (lib.flatten)
        (map (mapEntry: ''~.*£££.*?${mapEntry.host} ${mapEntry.cacheKey};''))
        (lib.concatStringsSep "\n    ")
      ];

      cacheIdentifierMap =
        # nginx
        ''
          map "$http_user_agent£££$http_host" $cacheidentifier {
              default $http_host;
              ${mapEntries}
          }
        '';

    in
    lib.mkIf cfg.enable

      {
        services.lancache.domainIndex = index;

        services.nginx = {
          enable = true;
          eventsConfig = # nginx
            ''
              worker_connections 4096;
              multi_accept on;
              use epoll;
            '';

          recommendedOptimisation = true;
          recommendedGzipSettings = true;

          appendConfig =
            #nginx
            ''
              # workers.conf
              worker_processes ${builtins.toString cfg.workerProcesses};
            '';

          appendHttpConfig = # nginx
            ''
              aio threads;


              # part of recommendedOptimisation
              #sendfile on;
              #tcp_nopush on;
              #tcp_nodelay on;
              #keepalive_timeout 65;

              # set in commonHttpConfig as 4096  which is not editable
              # types_hash_max_size 2048;


              # already done within commonHTTPConfig
              # there is a cfg.defaultMimieTypes option that can be used to override
              #include /etc/nginx/mime.types;
              #default_type application/octet-stream;

              # logs
              # access_log /var/log/nginx/access.log;
              # error_log /var/log/nginx/error.log;

              # part of cfg.recommendedGzipSettings
              # gzip on;



              # conf.d/20_proxy_cache_path.conf
              proxy_cache_path ${cfg.cacheLocation} levels=2:2 keys_zone=generic:${cfg.cacheIndexSize} inactive=${cfg.cacheMaxAge} max_size=${cfg.cacheDiskSize} min_free=${cfg.minFreeDisk} loader_files=1000 loader_sleep=50ms loader_threshold=300ms use_temp_path=off;

              # conf.d/30_maps.conf
              # map goes here
              ${cacheIdentifierMap}
            '';

          commonHttpConfig =
            # nginx
            ''
              # conf.d/10_log_format.conf
              log_format cachelog '[$cacheidentifier] $remote_addr / $http_x_forwarded_for - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" "$upstream_cache_status" "$host" "$http_range"';
              log_format cachelog-json escape=json '{"timestamp":"$msec","time_local":"$time_local","cache_identifier":"$cacheidentifier","remote_addr":"$remote_addr","forwarded_for":"$http_x_forwarded_for","remote_user":"$remote_user","status":"$status","bytes_sent":$body_bytes_sent,"referer":"$http_referer","user_agent":"$http_user_agent","upstream_cache_status":"$upstream_cache_status","host":"$host","http_range":"$http_range","method":"$request_method","path":"$request_uri","proto":"$server_protocol","scheme":"$scheme"}';


            '';
          # include /etc/nginx/sites-enabled/*.conf;
          # 10_generic.conf

          # Primary monolithic cache engine
          virtualHosts.generic = {

            listen = [
              {
                addr = "0.0.0.0";
                port = 80;
                extraParameters = [ "reuseport" ];
              }
              {
                addr = "[::]";
                port = 80;
                extraParameters = [ "reuseport" ];
              }
            ];

            extraConfig = # nginx
              ''
                access_log ${cfg.logPrefix}/access.log cachelog;
                error_log ${cfg.logPrefix}/error.log;

                # sites-available/cache.conf.d/10_root.conf
                resolver ${cfg.upstreamDns} ipv6=off;
              '';

            locations."/" = {
              extraConfig = # nginx
                ''
                  # include /etc/nginx/sites-available/cache.conf.d/root/*.conf;

                  # cache.conf.d/root/10_loop_detection.conf
                  # Abort any circular requests
                  if ($http_X_LanCache_Processed_By = $hostname) {
                    return 508;
                  }

                  proxy_set_header X-LanCache-Processed-By $hostname;
                  add_header X-LanCache-Processed-By $hostname,$http_X_LanCache_Processed_By;

                  # cache.conf.d/root/20_cache.conf
                  # Cache Location
                  slice ${cfg.sliceSize};
                  proxy_cache generic;

                  proxy_ignore_headers Expires Cache-Control;
                  proxy_cache_valid 200 206 ${cfg.cacheMaxAge};
                  proxy_set_header  Range $slice_range;

                  # Only download one copy at a time and use a large timeout so
                  # this really happens, otherwise we end up wasting bandwith
                  # getting the file multiple times.
                  proxy_cache_lock on;
                  # If it's taken over a minute to download a 1m file, we are probably stuck!
                  # Allow the next request to cache
                  proxy_cache_lock_age 2m;
                  # If it's totally broken after an hour, stick it in bypass (this shouldn't ever trigger)
                  proxy_cache_lock_timeout 1h;

                  # Allow the use of state entries
                  proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;

                  # Allow caching of 200 but not 301 or 302 as our cache key may not include query params
                  # hence may not be valid for all users
                  proxy_cache_valid 301 302 0;

                  # Enable cache revalidation
                  proxy_cache_revalidate on;

                  # Don't cache requests marked as nocache=1
                  proxy_cache_bypass $arg_nocache;

                  # 40G max file
                  proxy_max_temp_file_size 40960m;

                  # cache.conf.d/root/30_cache_key.conf 
                  proxy_cache_key      $cacheidentifier$uri$slice_range;

                  # 40_etags.conf 
                  # Battle.net Fix
                  proxy_hide_header ETag;

                  #90_upstream.conf 
                  # Upstream Configuration
                  proxy_next_upstream error timeout http_404;

                  # Proxy into the redirect handler
                  proxy_pass http://127.0.0.1:3128$request_uri;

                  proxy_redirect off;
                  proxy_ignore_client_abort on;

                  # Upstream request headers
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

                  # 99_gnu.conf
                  #In loving memory of Zoey "Crabbey" Lough. May she live on in the code

                  add_header X-Clacks-Overhead "GNU Terry Pratchett, GNU Zoey -Crabbey- Lough";
                  proxy_set_header X-Clacks-Overhead "GNU Terry Pratchett, GNU Zoey -Crabbey- Lough";

                  # 99_debug_header.conf 
                  # Debug Headers
                  add_header X-Upstream-Status $upstream_status;
                  add_header X-Upstream-Response-Time $upstream_response_time;
                  add_header X-Upstream-Cache-Status $upstream_cache_status;
                '';
            };
            # 20_lol.conf
            # Fix for League of Legends Updater
            locations."~ ^.+(releaselisting_.*|.version$)" = {
              proxyPass = "http://$host";
            };

            # 21_arenanet_manifest.conf
            # Fix for GW2 manifest
            locations."^~ /latest64" = {
              proxyPass = "http://$host$request_uri";
              extraConfig = ''
                proxy_cache_bypass 1;
                proxy_no_cache 1;
              '';
            };

            # 22_wsus_cabs.conf
            # Fix for WSUS authroot cab files
            locations."~* (authrootstl.cab|pinrulesstl.cab|disallowedcertstl.cab)$" = {
              proxyPass = "http://$host$request_uri";
              extraConfig = ''
                proxy_cache_bypass 1;
                proxy_no_cache 1;
              '';
            };

            # 23_steam_server_status.conf 
            locations."= /server-status" = {
              extraConfig = ''
                proxy_cache_bypass 1;
                proxy_no_cache 1;
              '';
            };

            # 90_lancache_heartbeat.conf
            locations." = /lancache-heartbeat" = {
              extraConfig =
                #nginx
                ''
                  add_header X-LanCache-Processed-By $hostname;
                  add_header X-Clacks-Overhead "GNU Terry Pratchett, GNU Zoey -Crabbey- Lough";
                  proxy_set_header X-Clacks-Overhead "GNU Terry Pratchett, GNU Zoey -Crabbey- Lough";
                  add_header 'Access-Control-Expose-Headers' '*';
                  add_header 'Access-Control-Allow-Origin' '*';
                '';
              return = 204;
            };

          };
          # 30_metrics.conf 
          # Metrics endpoint
          virtualHosts.metrics = {
            listen = [
              {
                addr = "localhost";
                port = 8080;
                extraParameters = [ "reuseport" ];
              }
            ];

            locations."/nginx_status" = {
              extraConfig = ''
                stub_status;
              '';
            };

          };
          virtualHosts.upstream =
            # 20_upstream.conf
            # Upstream server to proxy and handle inconsistent 302 redirects
            # All cache traffic is passed through this proxy to allow rewriting of redirects without caching

            # This is particularly important for sony / ps5 as upstreams redirect between them which confuses slice map on caching
            {
              # Internal bind on 3128, this should not be externally mapped
              listen = [
                {
                  addr = "localhost";
                  port = 3128;
                  extraParameters = [ "reuseport" ];
                }
              ];

              extraConfig =
                # nginx
                ''
                  # No access_log tracking as all requests to this instance are already logged through monolithic

                  access_log ${cfg.logPrefix}/upstream-access.log ${cfg.logFormat};
                  error_log ${cfg.logPrefix}/upstream-error.log;

                  #include /etc/nginx/sites-available/upstream.conf.d/*.conf;
                  #10_resolver.conf
                  resolver ${cfg.upstreamDns} ipv6=off;

                  #20_tracking.conf
                  # Header to track if resolved from upstream or 302 redirect
                  set $orig_loc 'upstream';
                '';

              #30_primary_proxy.conf
              # Proxy all requests to upstream
              locations = {
                "/" = {
                  # Simple proxy the request
                  proxyPass = "http://$host$request_uri";

                  extraConfig =
                    # nginx
                    ''
                      # Catch the errors to process the redirects
                      proxy_intercept_errors on;
                      error_page 301 302 307 = @upstream_redirect;
                    '';

                };

                #40_redirect_proxy.conf
                # Special location block to handle 302 redirects
                "@upstream_redirect" = {

                  # Pass to proxy and reproxy the request
                  proxyPass = "$saved_upstream_location";

                  extraConfig =
                    #nginx
                    ''
                      # Upstream_http_location contains the Location: redirection from the upstream server
                      set $saved_upstream_location '$upstream_http_location';

                      # Set debug header
                      set $orig_loc 'upstream-302';
                    '';

                };
              };
            };

            streamConfig = 
            /*
            #nix
            ''

              # stream settings
              # goes in cfg.streamConfig
              # stream {                                
              #   include /etc/nginx/stream.d/*.conf; # there is nothing there
              #   include /etc/nginx/stream-enabled/*; # the docker file linkes 10_sni.conf into stream-enabled
              # }

                #stream.d/log_format.conf
                log_format stream_basic '$remote_addr [$time_local] $protocol $status $ssl_preread_server_name $bytes_sent $bytes_received $session_time';

                # etc/nginx/stream-available(enabled)/10_sni.conf
                server {
                  listen 443 default_server;
                  server_name _;
                  resolver ${cfg.upstreamDns} ipv6=off;
                  proxy_pass  $ssl_preread_server_name:443;
                  ssl_preread on;

                  access_log ${cfg.logPrefix}/stream-access.log stream_basic;
                  error_log ${cfg.logPrefix}/stream-error.log;
                }
            '';
            */
        };
      };
}
