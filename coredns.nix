{ stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "coredns";
  version = "1.6.4";

  src = fetchurl {
    url = "https://github.com/coredns/coredns/releases/download/v${version}/coredns_${version}_linux_amd64.tgz";
    sha256 = "0npvfy788hbvl49m7kkj7h6qb6n90yqi0avdrcwk7nqildlv0f91";
  };

  sourceRoot = ".";
  installPhase = ''
    mkdir -p $out/bin
    mv coredns $out/bin/coredns
  '';
}
