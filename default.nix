{ stdenv
, jq, zerotierone, curl
, utillinux
}:

stdenv.mkDerivation rec {
  pname = "coredns-zt";
  version = "0.0";
  src = builtins.fetchGit ./.;

  patchPhase = ''
    substituteInPlace ./zt2hosts \
      --replace jq           '${jq}/bin/jq' \
      --replace curl         '${curl}/bin/curl' \
      --replace 'column -t'  '${utillinux}/bin/column -t'

    substituteInPlace ./zt2corefile \
      --replace jq           '${jq}/bin/jq' \
      --replace zerotier-cli '${zerotierone}/bin/zerotier-cli'
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp zt2hosts zt2corefile $out/bin
  '';
}
