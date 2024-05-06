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
, gnused
, rnp
, makeWrapper
}:
let
  version = lib.fileContents ./VERSION;
in
stdenvNoCC.mkDerivation {
  pname = "rel-sign";
  inherit version;
  src = ./.;
  buildInputs = [ bash gnupg rnp curl diffutils git unzip ];
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    mkdir -p "$out/bin"
    cp ./rel-sign.sh "$out/bin/rel-sign"
    "${gnused}/bin/sed" -i -e 's@__VERSION=.*$@__VERSION="${version}"@' "$out/bin/rel-sign"
    wrapProgram "$out/bin/rel-sign" \
      --prefix PATH : ${lib.makeBinPath [ bash gnupg rnp curl diffutils git unzip ]}
  '';
}
