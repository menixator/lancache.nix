# lancache.nix

This project aims to provide a lean configuration for users that want to run
[lancache](https://lancache.net) on their nix machines without having to resort
to running a docker container. 

It is designed to run alongside your configurations while keeping feature-parity
with the [upstream](https://github.com/lancachenet/monolithic) project.



The configurations are almost 1:1 with [lancachenet/monolithic](https://github.com/lancachenet/monolithic) and all credit for the nginx configurations
go to the lancache authors.


# Setup

```nix
services.lancache = {
  enable = true;
  cacheLocation = "/mnt/storage/lancache";
  logPrefix = "/var/log/nginx/lancache";
  # the listen address you want lancache to use.
  listenAddress = "10.0.0.2";

  # optional options with their defaults

  /*
    The upstream DNS servers the cache should use. The defaults are
    Cloudflare's DNS.

    Corresponds to the environment variable: `UPSTREAM_DNS` in standard
    lancache config.
  */
  upstreamDns = [
    "1.1.1.1"
    "1.0.0.1"
  ];

  /*
    The amount of disk space the container should use for caching data.
    Specified in gigabytes.

    Corresponds to the environment variable: `CACHE_DISK_SIZE` in
    standard lancache config.
  */
  cacheDiskSize = "1000g";

  /*
    Amount of index memory for the nginx cache manager. Lancache team
    recommends `250m` of index memory per `1TB` of `cacheDiskSize`

    Corresponds to the environment variable: `CACHE_INDEX_SIZE` in
    standard lancache config.
  */
  cacheIndexSize = "500m";

  /*
    The maximum amount of time a file should be held in cache. There is
    usually no reason to reduce this - the cache will automatically
    remove the oldest content if it needs the space.

    Corresponds to the environment variable: `CACHE_MAX_AGE` in standard
    lancache config.
  */
  cacheMaxAge = "3560d";

  /*
    Sets the minimum free disk space that must be kept at all times. When the
    available free space drops below the set amount for any reason, the cache
    server will begin pruning content to free up space. Specified in gigabytes.

    Corresponds to the environment variable: `CACHE_MAX_AGE` in standard
    lancache config.
  */
  minFreeDisk = "10g";

  /*
    See the guide before changing this. It WILL invalidate any currently cached data.

    link: https://lancache.net/docs/advanced/tuning-cache/#b---tweaking-slice-size

    Corresponds to the environment variable: `CACHE_SLICE_SIZE` in standard
    lancache config.
  */
  sliceSize = "1m";

  /*
    Sets the default logging format

    Nothing corresponds to this option in the standard lancache config
    Set it to cachelog-json to output json logs
  */
  logFormat = "cachelog";

  domainsPackage = pkgs.fetchFromGitHub {
    owner = "uklans";
    repo = "cache-domains";
    rev = "1f5897f4dacf3dab5f4d6fca2fe497d3327eaea9";
    sha256 = "sha256-xrHuYIrGSzsPtqErREMZ8geawvtYcW6h2GyeGMw1I88=";
  };

  # Defines the number of worker processes.
  workerProcesses = "auto";
};
```


These two are the major services that should be exposed:
- the catch-all http server that you can point the dns entries of cachable cdns to
- a transparent HTTPS proxy listening on `listenAddress:443`


One thing to note is that if you are listening to `0.0.0.0` on any of your
virtual hosts, it will clash with these configurations. The nixos nginx module
uses `0.0.0.0` as the `defaultListenAddress` so I recommend you change that

```nix
services.nginx.defaultListenAddresses = [ "192.168.100.2" ];
```


## Getting around address already in use errors
You might see errors like this:

```
nginx: [emerg] bind() to [::]:80 failed (98: Address already in use)
nginx: [emerg] bind() to [::]:443 failed (98: Address already in use)
```

This means you have vhosts already listening on `443`/`80`. You should assign
an extra ip address to your interface to get around this and use that ip
address for lancache.

Setting the `defaultListenAddress` (see above) is important too if you want your vhosts to just work™ without specifying listen addresses.

```nix
networking.interfaces.${interface}.ipv4.addresses = [
  {
    address = "192.168.100.3";
    prefixLength = 24;
  }
];

services.lancache.listenAddress = "192.168.100.3";
```


## Links/References:

- [uklans/cache-domains - domain lists](https://github.com/uklans/cache-domains)
- [Lancache Monolithic (upstream project)](https://github.com/lancachenet/monolithic)
- [Lancache Website](https://lancache.net)
- [Lancache.net docs](https://lancache.net/docs/)
