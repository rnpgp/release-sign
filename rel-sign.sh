#!/bin/sh
set -eu

# Make temporary folder
_mktemp() {
    local base=${1:-/tmp}
    if [[ $(uname) = Darwin ]]; then mktemp -d $base/rel-sign.XXXXXXXXXX
    else TMPDIR="$base" mktemp -d -t rel-sign.XXXXXXXXXX
    fi
}

# Print help message
function print_help() {
    printf \
"Sign releases from the GitHub repository with PGP key.
Usage: 
    ./rel-sign.sh -h, --help
    ./rel-sign.sh -r=user/repository -v=0.1.1 -k=7761E36F86C935A6
    -r, --repo - repository, in the format username/repository
    -v, --version - version, in the format x.y.z, without leading v
    -k, --key - signing key id, fingerprint or email
    -gpg - use gpg instead of rnp for signing.
    -pparams - addition OpenPGP params, like '--homedir .rnp', '--keyfile seckey.asc', etc.\n"
}

# Extract parameters
if [ $# -eq 0 ]; then
    print_help
    exit 0
fi

PPARAMS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo*|-r*)
      if [[ "$1" != *=* ]]; then shift; fi # Value is next arg if no `=`
      REPO="${1#*=}"
      REPOLAST=`basename ${REPO}`
      ;;
    --version*|-v*)
      if [[ "$1" != *=* ]]; then shift; fi
      VERSION="${1#*=}"
      ;;
    --key*|-k*)
      if [[ "$1" != *=* ]]; then shift; fi
      KEY="${1#*=}"
      ;;
    --gpg)
      USEGPG=1
      ;;
    --pparams*)
      if [[ "$1" != *=* ]]; then shift; fi
      PPARAMS="${1#*=}"
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      >&2 printf "Invalid argument: $1\nUse --help or -h to get list of available arguments.\n"
      exit 1
      ;;
  esac
  shift
done

# Check whether all parameters are specified.
if [ -z ${REPO+x} ]; then
    printf "Please specify repository via -r or --repo argument.\n"
    exit 1
fi
if [ -z ${VERSION+x} ]; then
    printf "Please specify release version via -v or --version argument.\n"
    exit 1
fi
if [ -z ${KEY+x} ]; then
    printf "Signing key was not specified - so default one will be used.\n"
fi

# Fetch repository and release tarball/zip.
printf "Fetching repository and releases...\n"
set -x
TMPDIR=$(_mktemp)
pushd ${TMPDIR} > /dev/null

git clone https://github.com/${REPO}
pushd ${REPOLAST} > /dev/null
git checkout v${VERSION}
popd > /dev/null

# Check .tar.gz
wget https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz
tar xf v${VERSION}.tar.gz
diff -qr --exclude=".git" ${REPOLAST} ${REPOLAST}-${VERSION}
rm -rf ${REPOLAST}-${VERSION}

# Check .zip
wget https://github.com/${REPO}/archive/refs/tags/v${VERSION}.zip
unzip -qq v${VERSION}.zip
diff -qr --exclude=".git" ${REPOLAST} ${REPOLAST}-${VERSION}
rm -rf ${REPOLAST}-${VERSION}
popd > /dev/null

# Sign
KEYCMD=""
if [ -z ${USEGPG+x} ]; then
    # Using the rnp - default
    if [ ! -z ${KEY+x} ]; then
        KEYCMD="-u ${KEY}"
    fi
    rnp --sign --detach --armor ${KEYCMD} ${PPARAMS} ${TMPDIR}/v${VERSION}.tar.gz --output v${VERSION}.tar.gz.asc
    rnp --sign --detach --armor ${KEYCMD} ${PPARAMS} ${TMPDIR}/v${VERSION}.zip --output v${VERSION}.zip.asc
else
    # Using the gpg
    if [ ! -z ${KEY+x} ]; then
        KEYCMD="-u ${KEY}"
    fi
    gpg --armor --detach-sign ${KEYCMD} ${PPARAMS} --output v${VERSION}.tar.gz.asc ${TMPDIR}/v${VERSION}.tar.gz
    gpg --armor --detach-sign ${KEYCMD} ${PPARAMS} --output v${VERSION}.zip.asc ${TMPDIR}/v${VERSION}.zip
fi

printf "Signatures are stored in files v${VERSION}.tar.gz.asc and v${VERSION}.zip.asc. \n";
rm -rf ${TMPDIR}
