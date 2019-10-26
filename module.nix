{ config, lib, pkgs, ... }:

with lib;
with builtins;

let
  cfg = config.services.zerotierone-with-dns;

  coredns = pkgs.callPackage ./coredns.nix { };
  dnscrypt-proxy = pkgs.callPackage ./dnscrypt-proxy.nix { };

  coredns-zt = pkgs.callPackage ./. {
    zerotierone = config.services.zerotierone.package;
  };

  zt-networks = lib.mapAttrsToList (_: v: v) cfg.networks;

  zt-dnscrypt-port = cfg.port + 1000;

  network-string = lib.concatStringsSep " " (lib.mapAttrsToList (z: n: "${z}:${n}") cfg.networks);

  zt-coredns-services = {
    zt-dns-init = {
      description = "setup ZeroTier DNS files";
      script = ''
        mkdir -p /etc/coredns-zt/
        touch /etc/coredns-zt/dns-blacklist.txt
      '';
      serviceConfig.Type = "oneshot";
    };

    zt-dnscrypt =
      let
        dnscrypt-config = pkgs.runCommand "dnscrypt-proxy.toml" {} ''
          substitute ${./dnscrypt-proxy.toml.in} $out \
            --subst-var-by PORT '${toString zt-dnscrypt-port}' \
        '';
      in {
        description = "dnscrypt-proxy2 service backend for CoreDNS";

        script = ''
          exec ${dnscrypt-proxy}/bin/dnscrypt-proxy -config ${dnscrypt-config}
        '';

        serviceConfig = {
          NoNewPrivileges = true;
          DynamicUser = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectHome = true;
          ProtectSystem = true;

          LimitNPROC = 512;
          LimitNOFILE = 1048576;
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
          Restart = "on-failure";
        };

        requires = [ "network-online.target" "zt-dns-init.service" ];
        after    = [ "network-online.target" "zt-dns-init.service" ];
      };

    zt-coredns = {
      description = "CoreDNS service for ZeroTier networks";

      preStart = ''
        ${coredns-zt}/bin/zt2corefile ${toString cfg.port} ${network-string} > \
          /etc/coredns-zt/Corefile
        echo Corefile setup complete
      '';

      requires = [ "zerotierone.service" "zt-dnscrypt.service" "zt-dns-init.service" ];
      after    = [ "zerotierone.service" "zt-dnscrypt.service" "zt-dns-init.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        PermissionsStartOnly = true;
        LimitNPROC = 512;
        LimitNOFILE = 1048576;
        CapabilityBoundingSet = "cap_net_bind_service";
        AmbientCapabilities = "cap_net_bind_service";
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectSystem = true;
        PrivateTmp = true;
        DynamicUser = true;
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
        ExecStart  = "${coredns}/bin/coredns -conf /etc/coredns-zt/Corefile";
        Restart = "on-failure";
      };
    };

    zt-dns-update-hosts = {
      description = "hosts(5) update for ZeroTier DNS";
      startAt = "minutely";

      script = ''
        echo updating ZeroTier DNS hosts file...
        ${coredns-zt}/bin/zt2hosts ${network-string} > /tmp/hosts
        mv /tmp/hosts /etc/coredns-zt/hosts
        echo OK, done
      '';

      unitConfig.ConditionPathExists = "/etc/coredns-zt/api-token";
      serviceConfig = {
        PrivateTmp = true;
        EnvironmentFile = "/etc/coredns-zt/api-token";
      };

      requires = [ "zt-coredns.service" "zt-dns-init.service" ];
      after    = [ "zt-coredns.service" "zt-dns-init.service" ];
    };

    zt-dns-update-blacklist = {
      description = "daily dnscrypt-proxy2 blacklist update";
      # startAt = "daily";

      path = [ pkgs.curl ];
      script = ''
        echo Downloading blacklist...
        curl -s -o /tmp/dns-blacklist-new.txt \
          https://download.dnscrypt.info/blacklists/domains/mybase.txt
        mv /tmp/dns-blacklist-new.txt /etc/coredns-zt/dns-blacklist.txt
        echo OK
      '';

      serviceConfig = {
        PrivateTmp = true;
      };

      requires = [ "zt-dnscrypt.service" ];
      after    = [ "zt-dnscrypt.service" ];
    };
  };
in
{
  options.services.zerotierone-with-dns = {
    enable = mkEnableOption "Private DNS for your ZeroTier One Network";

    port = mkOption {
      type        = types.int;
      default     = 53;
      example     = 1053;
      description = "Port for DNS requests";
    };

    networks = mkOption {
      type        = types.attrsOf types.str;
      default     = {};
      example     = {
        "home-network.zt" = "...";
      };
      description = "Mapping of ZeroTier One networks to private DNS names";
    };
  };

  config = lib.mkIf cfg.enable {
    # We always enable ZeroTier one and pull the list of network IDs from it.
    services.zerotierone = {
      enable = true;
      joinNetworks = zt-networks;
    };

    # Punch open the firewall.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
    networking.firewall.allowedUDPPorts = [ cfg.port ];

    # Set the nameserver to localhost; this overrides everything since DNScrypt
    # does the rest. It might be nice to add an option for including an extra
    # list of servers if you want in DNSCrypt...
    networking.nameservers = [ "127.0.0.1" ];

    # Now pull in all the services.
    systemd.services = zt-coredns-services;
  };
}
