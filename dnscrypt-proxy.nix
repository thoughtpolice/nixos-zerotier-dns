{ stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "dnscrypt-proxy";
  version = "2.0.29-beta.3";

  src = fetchurl {
    url    = "https://github.com/DNSCrypt/${pname}/releases/download/${version}/${pname}-linux_x86_64-${version}.tar.gz";
    sha256 = "1pn9snpqs265hl06p15mfqgah7nxvh3zhl5waw778kbv79s8ah35";
  };

  installPhase = ''
    mkdir -p $out/bin
    mv dnscrypt-proxy $out/bin/dnscrypt-proxy
  '';
}
