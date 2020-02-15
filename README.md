# ZeroTier DNS for NixOS

This is a simple NixOS module to run an auto-updating ZeroTier DNS setup, based
on [CoreDNS](https://coredns.io) and [dnscrypt-proxy
2.x](https://github.com/dnscrypt/dnscrypt-proxy). It assumes you're using
https://my.zerotier.com for now.

CoreDNS serves all DNS requests on local interfaces (including configured ZT
interfaces). For ZT networks you attach a zone name to, the network members are
periodically scanned and added to a `hosts(5)` file, which is monitored by
CoreDNS and updated in real time. This lets it serve up to date IPs.

The record entries are of the form `<name>.<zone>`, where `<name>` comes from
the node name assigned in ZeroTier. So pick a good lower-case single-word (no
spaces, hypens etc ok) name for your machines. (I like Legend of Zelda
characters.) There are also IDs added of the form `<nodeid>.<zone>` as well, for
totally unambiguous entries.

For requests to non-ZeroTier network members, the request is forwarded from
CoreDNS to a local copy of `dnscrypt-proxy` that serves the request from an
upstream resolver, completely transparently. (Therefore, while you can pick any
arbitrary DNS name, it's probably best to use a non-standard gTLD for your
networks, such as `.zt`).

`dnscrypt-proxy` is also served with a daily-updated blacklist of bad DNS names
that are sinkholed automatically to help preserve privacy, and the upstream
resolvers are non-logging DNSCrypt servers, rotated randomly.

Put together, this means any NixOS machine running this service can be run as
the sole DNS resolver for any computer attached to the same ZeroTier network --
with the added benefit of DNS privacy, ad/malware sinkholing, and names for
ZeroTier members.

## Design

The primary motivation for this setup was so that my iPhone's ZeroTier
configuration can use a single DNS entry when connected -- fallbacks only occur
on DNS timeout, not resolution failure, so the canonical ZT DNS server also
needs to serve upstream domains, too, to be useful. (Because iOS ties the
DNS/VPN configuration together, fallbacks generally aren't needed, since a
disconnect punts you to other DNS servers anyway as part of the network change.
For other devices, you can use a service like `9.9.9.9`, `1.1.1.1`, or `8.8.8.8`
as your fallback resolver when you're not connected to the network.)

Eventually, I want this to be able to scrape Docker 6PLANE-based IPv6 network
addresses assigned to containers on a ZeroTier network, giving "auto-magical"
Docker DNS to any container in the network.

The machine running this service will serve DNS entries on *all* ZeroTier
networks it's attached to, for *all* members in *all* networks. Why do this?
Because it's easier than doing complex routing at the network stack and
sinkholing bad names based on the interface (though I think ZeroTier is capable
of this.) This means that a member of network `foo.net1.zt` will be able to
query the DNS server for `bar.net2.zt` and get a valid A/AAAA record, but unless
they're *both* part of `net2`, it won't be able to route/connect anyway.

Furthermore, serving only one set of hosts to one interface and falling back to
an upstream is inconvenient when you're connected to *multiple* networks. For
instance, if my server (`10.0.x.1`) is running this DNS setup, and is part of
network `net1` and `net2`, and my desktop (`10.0.x.2`) is also on both of these
networks, I can pick a network IP my server has in either network -- say
`10.0.1.1` for `net1`, `10.0.2.1` for `net2` -- as my DNS server. Then I can
resolve the servername for *both* networks transparently, with either choice.

If the server only served requests for `.net1.zt` on `10.0.1.1` and `.net2.zt`
on `10.0.2.1`, then setting my desktop's DNS to `10.0.1.1` means it cannot
resolve names for `net2.zt`. Even though my server and desktop are both on the
same networks, the full set of names does not resolve.

## Usage

``` bash
$ sudo -i
mkdir -p /etc/coredns-zt
echo "ZT_API_TOKEN=secretoken" > /etc/coredns-zt/api-token
chmod 0600 /etc/coredns-zt/api-token
```

Import the `./module.nix` from somewhere. Then, in `configuration.nix`,

``` nix
{
  services.zerotierone-with-dns = {
    enable = true;
    networks = {
      "homenet.zt" = "<ZEROTIER NETWORK ID>";
      "gamenet.zt" = "<ZEROTIER NETWORK ID>";
    };
  };
}
```

That's it. This will automatically enable `services.zerotierone`, so you don't
have to. CoreDNS will refresh its zone entries from a `hosts(5)` file under
`/etc/coredns-zt` through timer services every minute. It also configures your
NixOS machine to use `127.0.0.1` as the local nameserver, since
`dnscrypt-proxy` will handle upstream connections.

Now, try something like:

``` bash
nixos-rebuild build && sudo nixos-rebuild switch
dig aaaa zelda.gamenet.zt
dig aaaa google.com
dig a    adservice.google.co.za # sinkholed
```

CoreDNS only runs on `localhost` bound ports, and any ZeroTier interfaces you
configure.

# Details

Here are how the two tools work.

## `zt2hosts`

Given a list of ZeroTier network IDs with hostnames attached, this scans the
list of network members and outputs a `hosts(5)` compatible hosts file. It
supports the default auto-assigned IPv4 network IPs, and also emits v6 records
for RFC4139 and 6PLANE networks if those are enabled.

The general format is `zt2hosts <ZONE>:<NETWORK ID>`, and the output is
generated on stdout. The format of `<ZONE>` should be the complete suffix; for
instance, if your network is named 'home network' (in the ZeroTier UI), you
might name the zone `homenet.zt`

``` sh
export ZT_API_TOKEN=...
./zt2hosts $ZONE:$NETWORK_ID... > homenet.hosts
```

It assumes that the name of the machines in the network are a single word (no
spaces, hypens etc ok), and that the name will serve as a component of the
hostname and aliases. For example, I have a desktop named 'Zelda' and a server
named 'Link', with RFC4139 and 6PLANE enabled, so the output records might look
like:

```bash
./zt2hosts "homenet.zt:$NETWORK_ID"
127.0.0.1      localhost
10.147.20.ABC  zelda.homenet.zt       <ZELDA NODE ID>.homenet.zt
10.147.20.XYZ  link.homenet.zt        <LINK NODE ID>.homenet.zt
::1            localhost              ip6-localhost  ip6-loopback
fd35:...:64b4  zelda.homenet.zt       <ZELDA NODE ID>.homenet.zt # RFC4139
fcae:...:0001  zelda.homenet.zt       <ZELDA NODE ID>.homenet.zt # 6PLANE
fd35:...:4682  link.homenet.zt        <LINK NODE ID>.homenet.zt  # RFC4139
fcae:...:0001  link.homenet.zt        <LINK NODE ID>.homenet.zt  # 6PLANE
```

The intention is that this file can be fed to the CoreDNS `hosts` plugin.

Note that the FQDNs are unambiguous and the short hostname is not included; this
is so that a single CoreDNS instance can service multiple ZeroTier networks at
once without ambiguity.

## zt2corefile

This is a one-shot tool that will take a DNS port, list of network/hostname
pairs like above, and emit a fragment of a CoreDNS `Corefile` that is intended
to route DNS requests for a zones to the right hosts file.

## `dnscrypt-proxy`

The upstream NixOS module for `dnscrypt-proxy` only supports the original 1.x
branch, not `dnscrypt-proxy` 2.x. Therefore we install the static binary on our
own and run it "privately" as part of this NixOS module.

The usage of `dnscrypt-proxy` is largely intended to be an implementation
detail; we could swap out another resolver, but it has a lot of nice features
and works well.

In theory, `dnscrypt-proxy` 2 cloaking rules can effectively replace the usage
of CoreDNS + `hosts(5)`, but I only chose `dnscrypt-proxy` after realizing this
and having CoreDNS in place. But I think having each of these do what they were
intended to do (private, dedicated upstream resolver vs "dynamic" DNS proxy) is
perhaps better in the long run.

# Bugs

It's a DNS server setup, so it's sensitive to fuck ups. If it fucks up, the
machines using it as a DNS server will probably be OK, if you have fallbacks
are configured, you just won't route ZeroTier names, and you'll get more ads.

But, the NixOS machine running this will probably need to be fixed manually,
since it won't be able to resolve cache.nixos.org for
downloads/`nixos-rebuild`. (Personally I just kept around a copy of CoreDNS and
then wrote a `Corefile` to do temporary serving for rebuilds in such a case,
but I can't help you too much.) Good luck.

# License

MIT. See `LICENSE.txt` for terms of copyright and redistribution.
