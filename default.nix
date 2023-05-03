# See: https://nixos.wiki/wiki/Shell_Scripts#Packaging
#
{ pkgs
, lib
, stdenvNoCC
, curl
, diffutils
, git
, unzip
, bash
, gnupg
, rnp
, makeWrapper
}:
stdenvNoCC.mkDerivation {
  pname = "rel-sign";
  version = "0.1.1";
  src = ./.;
  buildInputs = [ bash gnupg rnp curl diffutils git unzip ];
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    mkdir -p $out/bin
    cp ./rel-sign.sh $out/bin/rel-sign
    wrapProgram $out/bin/rel-sign \
      --prefix PATH : ${lib.makeBinPath [ bash gnupg rnp curl diffutils git unzip ]}
  '';
}
