#!/bin/bash
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

set -e

# Make temporary folder
function _mktemp() {
    local base="/tmp"
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
    -d, --debug - dump commands which are executed.
    --pparams - all further parameters will be passed to the OpenPGP backend, like '--homedir .rnp', '--keyfile seckey.asc', etc.\n"
}

# Extract parameters
if [ $# -eq 0 ]; then
    print_help
    exit 0
fi

PPARAMS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --repo*|-r*)
      if [[ "$1" == *=* ]]; then REPO="${1#*=}"
      else shift; REPO="${1}"; fi
      REPOLAST=$(basename "${REPO}")
      ;;
    --version*|-v*)
      if [[ "$1" == *=* ]]; then VERSION="${1#*=}"
      else shift; VERSION="${1}"; fi
      ;;
    --key*|-k*)
      if [[ "$1" == *=* ]]; then KEY="${1#*=}"
      else shift; KEY="${1}"; fi
      ;;
    --gpg)
      USEGPG=1
      ;;
    --src*|-s*)
      if [[ "$1" == *=* ]]; then SRCDIR="${1#*=}"
      else shift; SRCDIR="${1}"; fi
      SRCDIR=$(realpath "${SRCDIR}")
      if [ ! -d "${SRCDIR}" ]; then
          >&2 printf "Directory %s doesn't exist.\n" "${SRCDIR}"
          exit 1
      fi
      >&2 printf "Comparing with sources from %s\n" "${SRCDIR}"
      ;;
    --debug|-d)
      set -x
      ;;
    --pparams)
      shift
      PPARAMS=("$@")
      break
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      >&2 printf "Invalid argument: %s\nUse --help or -h to get list of available arguments.\n" "$1"
      exit 1
      ;;
  esac
  shift
done

# Check whether all parameters are specified.
if [[ -z "${REPO}" ]]; then
    >&2 printf "Please specify repository via -r or --repo argument.\n"
    exit 1
fi
if [[ -z "${VERSION}" ]]; then
    >&2 printf "Please specify release version via -v or --version argument.\n"
    exit 1
fi
if [[ -z "${KEY}" ]]; then
    >&2 printf "Signing key was not specified - so default one will be used.\n"
fi

# Fetch repository and release tarball/zip.
TMPDIR=$(_mktemp)
pushd "${TMPDIR}" > /dev/null
>&2 printf "Working directory is %s\n" "$(pwd)"

if [[ -z "${SRCDIR}" ]]; then
    >&2 printf "Fetching repository %s\n" "${REPO}"
    git clone --quiet "https://github.com/${REPO}"
    pushd "${REPOLAST}" > /dev/null
    >&2 printf "Checking out tag %s\n" "v${VERSION}"
    git checkout --quiet "v${VERSION}"
    popd > /dev/null
    SRCDIR=${REPOLAST}
fi

# Check .tar.gz
URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
>&2 printf "Downloading %s\n" "${URL}"
wget -q "${URL}"
tar xf "v${VERSION}.tar.gz"
>&2 printf "Checking unpacked tarball against sources in %s\n" "$(realpath "${SRCDIR}")"
diff -qr --exclude=".git" "${SRCDIR}" "${REPOLAST}-${VERSION}"
rm -rf "${REPOLAST}-${VERSION}"

# Check .zip
URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.zip"
>&2 printf "Downloading %s\n" "${URL}"
wget -q "${URL}"
unzip -qq "v${VERSION}.zip"
>&2 printf "Checking unpacked zip archive against sources in %s\n" "$(realpath "${SRCDIR}")"
diff -qr --exclude=".git" "${SRCDIR}" "${REPOLAST}-${VERSION}"
rm -rf "${REPOLAST}-${VERSION}"
popd > /dev/null

# Sign
>&2 printf "Signing tarball and zip\n"
if [[ -n "${KEY}" ]]; then
    # Same for RNP and GnuPG
    PPARAMS=("-u" "${KEY}" "${PPARAMS[@]}")
fi
if [[ -z "${USEGPG}" ]]; then
    # Using the rnp - default
    rnp --sign --detach --armor "${PPARAMS[@]}" "${TMPDIR}/v${VERSION}.tar.gz" --output "v${VERSION}.tar.gz.asc"
    rnp --sign --detach --armor "${PPARAMS[@]}" "${TMPDIR}/v${VERSION}.zip" --output "v${VERSION}.zip.asc"
else
    # Using the gpg
    gpg --armor "${PPARAMS[@]}" --output "v${VERSION}.tar.gz.asc" --detach-sign "${TMPDIR}/v${VERSION}.tar.gz"
    gpg --armor "${PPARAMS[@]}" --output "v${VERSION}.zip.asc" --detach-sign "${TMPDIR}/v${VERSION}.zip"
fi

>&2 printf "Signatures are stored in files %s and %s.\n" "v${VERSION}.tar.gz.asc" "v${VERSION}.zip.asc";
rm -rf "${TMPDIR}"
