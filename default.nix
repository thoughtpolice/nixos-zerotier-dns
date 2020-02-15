{ stdenv, fetchFromGitHub
, jq, zerotierone, curl
, utillinux
}:
let
  gitignoreSrc = fetchFromGitHub {
    owner = "hercules-ci";
    repo = "gitignore";
    # put the latest commit sha of gitignore Nix library here:
    rev = "f9e996052b5af4032fe6150bba4a6fe4f7b9d698";
    # use what nix suggests in the mismatch message here:
    sha256 = "sha256:0jrh5ghisaqdd0vldbywags20m2cxpkbbk5jjjmwaw0gr8nhsafv";
  };
  inherit (import gitignoreSrc {}) gitignoreSource;
in
stdenv.mkDerivation rec {
  pname = "coredns-zt";
  version = "0.0";
  src = gitignoreSource ./.;

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
