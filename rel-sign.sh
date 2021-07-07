#!/bin/sh
# Copyright (c) 2021 Ribose Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

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
    -s, --src - use specified folder for release sources comparison instead of downloading from GitHub.
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
    --src*|-s*)
      if [[ "$1" != *=* ]]; then shift; fi
      SRCDIR=`realpath "${1#*=}"`
      if [ ! -d ${SRCDIR} ]; then
          printf "Directory ${SRCDIR} doesn't exist.\n"
          exit 1
      fi
      printf "Comparing with sources from ${SRCDIR}\n"
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

if [ -z ${SRCDIR+X} ]; then
    git clone https://github.com/${REPO}
    pushd ${REPOLAST} > /dev/null
    git checkout v${VERSION}
    popd > /dev/null
    SRCDIR=${REPOLAST}
fi

# Check .tar.gz
wget https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz
tar xf v${VERSION}.tar.gz
diff -qr --exclude=".git" ${SRCDIR} ${REPOLAST}-${VERSION}
rm -rf ${REPOLAST}-${VERSION}

# Check .zip
wget https://github.com/${REPO}/archive/refs/tags/v${VERSION}.zip
unzip -qq v${VERSION}.zip
diff -qr --exclude=".git" ${SRCDIR} ${REPOLAST}-${VERSION}
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
