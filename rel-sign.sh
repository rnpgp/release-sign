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

set -eu

info() {
	if [[ -n "${VERBOSE}" || -n "${DEBUG}" ]]; then
		echo "$*"
	fi
}

debug() {
	if [[ -n "${DEBUG}" ]]; then
		>&2 echo "[debug] $*"
	fi
}

warn() {
	>&2 echo "$*"
}

infop() {
	if [[ -n "${VERBOSE}" || -n "${DEBUG}" ]]; then
		printf "$@"
	fi
}

debugp() {
	if [[ -n "${DEBUG}" ]]; then
		>&2 printf "[debug] "
		>&2 printf "$@"
	fi
}

warnp() {
	>&2 printf "$@"
}

# Echo command (if verbose mode)
ecdo() {
	for segment in "$@"; do
		infop " ${segment}"
	done
	info
	"$@"
}

declare -a TEMPDIRS=()

cleanup() {
	for tmpdir in "${TEMPDIRS[@]-}"; do
		debugp "Removing tmpdir '${tmpdir}'"
		rm -rf "${tmpdir}"
	done
}

trap cleanup EXIT

# Make temporary folder
_mktemp() {
	local base="/tmp"
	local tmpdir_format=rel-sign.XXXXXXXXXX
	local tmpdir
	tmpdir=$(
		if [[ $(uname) = Darwin ]]; then
			mktemp -d "${base}/${tmpdir_format}"
		else
			TMPDIR="$base" mktemp -d -t "${tmpdir_format}"
		fi
	)
	TEMPDIRS+=("${tmpdir}")
	echo "${tmpdir}"
}

declare __PROGNAME="${0##*/}"

# Print help message
print_help() {
	printf "Sign releases from the GitHub repository with PGP key.
Usage:
    \e[1m${__PROGNAME}\e[m \e[4mOPTIONS...\e[m
Example:
    \e[1m${__PROGNAME}\e[m -r=user/repository -v=0.1.1 -k=7761E36F86C935A6
Options:
    -h, --help      - show this help message and abort
    -r, --repo      - repository, in the format "username/repository"
    -v, --version   - version, in the format "x.y.z", without leading "v"
    -k, --key       - signing key id, fingerprint or email
    --key-env       - name of env variable holding content of signing key
                      (if not using -k)
    --gpg           - use gpg instead of rnp for signing
    -s, --src       - use specified folder for release sources
                      comparison instead of downloading from GitHub
    -d, --debug     - dump commands which are executed
    -V, --verbose   - output progress logs
    --pparams       - all further parameters will be passed to the
                      OpenPGP backend, like:
                        '--homedir .rnp'
                        '--keyfile seckey.asc'
                        etc."
	echo
}

declare USEGPG=
declare REPO=
declare REPOLAST=
declare VERSION=
declare SRCDIR=
declare PPARAMS=()
declare KEY=
declare KEY_ENV=
declare DEBUG=
declare VERBOSE=

# Extract parameters
parse-opts() {
	if [[ $# -eq 0 ]]; then
		print_help
		exit 0
	fi

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--repo*|-r*)
				if [[ "$1" == *=* ]]; then
					REPO="${1#*=}"
				else
					shift
					REPO="${1}"
				fi
				REPOLAST=$(basename "${REPO}")
				;;
			--version*|-v*)
				if [[ "$1" == *=* ]]; then
					VERSION="${1#*=}"
				else
					shift
					VERSION="${1}"
				fi
				;;
			--key|-k)
				if [[ "$1" == *=* ]]; then
					KEY="${1#*=}"
				else
					shift
					KEY="${1}"
				fi
				;;
			--key-env|-key-*)
				if [[ "$1" == *=* ]]; then
					KEY_ENV="${1#*=}"
				else
					shift
					KEY_ENV="${1}"
				fi
				;;
			--gpg)
				USEGPG=1
				;;
			--src*|-s*)
				if [[ "$1" == *=* ]]; then
					SRCDIR="${1#*=}"
				else
					shift
					SRCDIR="${1}"
				fi

				SRCDIR=$(realpath "${SRCDIR}")

				if [[ ! -d "${SRCDIR}" ]]; then
					warnp "Directory %s doesn't exist.\n" "${SRCDIR}"
					exit 1
				fi

				warnp "Comparing with sources from %s\n" "${SRCDIR}"
				;;
			--debug|-d)
				set -x
				DEBUG=1
				;;
			--verbose|-V)
				VERBOSE=1
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
				warnp "Invalid argument: %s\nUse --help or -h to get list of available arguments.\n" "$1"
				exit 1
				;;
		esac
		shift
	done
}

# Check whether all parameters are specified.
validate-parameters() {
	if [[ -z "${REPO}" ]]; then
		warnp "Please specify repository via -r or --repo argument.\n"
		exit 1
	fi

	if [[ -z "${VERSION}" ]]; then
		warnp "Please specify release version via -v or --version argument.\n"
		exit 1
	fi

	if [[ -z "${KEY}" && -z "${KEY_ENV}" ]]; then
		warnp "Signing key was not specified - so default one will be used.\n"
	fi
}

# Fetch repository and release tarball/zip.
fetch-repo() {
	infop "Working directory is %s\n" "$(pwd)"

	if [[ -z "${SRCDIR}" ]]; then
		infop "Fetching repository %s\n" "${REPO}"
		git clone --quiet "https://github.com/${REPO}"
		pushd "${REPOLAST}" > /dev/null
		infop "Checking out tag %s\n" "v${VERSION}"
		git checkout --quiet "v${VERSION}"
		popd > /dev/null
		SRCDIR=${REPOLAST}
	fi
}

declare prerequisites=(
	diff
	git
	tar
	unzip
	wget
)

# Check if all prerequisites are met
check-prerequisites() {
	local unsatisfied=()

	if [[ -n "${USEGPG}" ]]; then
		prerequisites+=("gpg")
	else
		prerequisites+=("rnp")
	fi

	for prereq in "${prerequisites[@]}"; do
		if ! command -v "${prereq}" > /dev/null; then
			unsatisfied+=("${prereq}")
		fi
	done

	if [[ "${#unsatisfied[@]}" -gt 0 ]]; then
		warn "Error: the following prerequisites are unsatisfied.  Aborting."
		for unsat in "${unsatisfied[@]}"; do
			warn "  ${unsat}"
		done
		exit 1
	fi
}

# Check .tar.gz
check-targz() {
	local url="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
	infop "Downloading %s\n" "${url}"
	wget -q "${url}"
	tar xf "v${VERSION}.tar.gz"
	infop "Checking unpacked tarball against sources in %s\n" "$(realpath "${SRCDIR}")"
	diff -qr --exclude=".git" "${SRCDIR}" "${REPOLAST}-${VERSION}"
	rm -rf "${REPOLAST}-${VERSION}"
}

# Check .zip
check-zip() {
	local url="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.zip"
	infop "Downloading %s\n" "${url}"
	wget -q "${url}"
	unzip -qq "v${VERSION}.zip"
	infop "Checking unpacked zip archive against sources in %s\n" "$(realpath "${SRCDIR}")"
	diff -qr --exclude=".git" "${SRCDIR}" "${REPOLAST}-${VERSION}"
	rm -rf "${REPOLAST}-${VERSION}"
}

sign() {
	info "Signing tarball and zip"
	if [[ -n "${KEY}" ]]; then
		# Same for RNP and GnuPG
		PPARAMS=("-u" "${KEY}" "${PPARAMS[@]+${PPARAMS[@]}}")
	fi

	local signing_key=
	if [[ -n "${KEY_ENV}" ]]; then
		# Same for RNP and GnuPG
		signing_key="$(cat "${KEY_ENV}")"
	fi

	local -a cmd1=()
	local -a cmd2=()

	for ext in {zip,tar.gz}; do
		if [[ -z "${USEGPG}" ]]; then
		# Using rnp - default
			cmd1=(rnp --sign --detach --armor)
			cmd2=("${PPARAMS[@]+${PPARAMS[@]}}" "${TMPDIR}/v${VERSION}.${ext}" --output "v${VERSION}.${ext}.asc")
		else
		# Using gpg
			cmd1=(gpg --armor)
			cmd2=("${PPARAMS[@]+${PPARAMS[@]}}" --output "v${VERSION}.${ext}.asc" --detach-sign "${TMPDIR}/v${VERSION}.${ext}")
		fi

		if [[ -n "${KEY_ENV}" ]]; then
			"${cmd1[@]}" --keyfile <(echo "${signing_key}") "${cmd2[@]}"
		else
			"${cmd1[@]}" "${cmd2[@]}"
		fi
	done

	# Calculate hashes as well
	pushd "${TMPDIR}" > /dev/null
	info sha256sum "v${VERSION}.zip" "v${VERSION}.tar.gz" ">" "v${VERSION}.sha256"
	sha256sum "v${VERSION}.zip" "v${VERSION}.tar.gz" > "v${VERSION}.sha256"
	popd > /dev/null
	mv "${TMPDIR}/v${VERSION}.sha256" .

	infop "Signatures are stored in files %s and %s.\n" "v${VERSION}.tar.gz.asc" "v${VERSION}.zip.asc";
}

verify() {
	# Validate hashes first
	cp "v${VERSION}.sha256" "${TMPDIR}/v${VERSION}.sha256"
	pushd "${TMPDIR}" > /dev/null
	ecdo sha256sum --quiet -c "v${VERSION}.sha256"
	popd > /dev/null

	# Verify signatures
	if [[ -z "${USEGPG}" ]]; then
		for ext in {zip,tar.gz}; do
			# Work around RNP's option
			cp "${TMPDIR}/v${VERSION}.${ext}" .
			ecdo rnp --verify "v${VERSION}.${ext}.asc"
			rm "v${VERSION}.${ext}"
		done
	else
		for ext in {zip,tar.gz}; do
			ecdo gpg --verify "v${VERSION}.${ext}.asc" "${TMPDIR}/v${VERSION}.${ext}"
		done
	fi
}

main() {
	parse-opts "$@"
	check-prerequisites
	validate-parameters

	local tmpdir
	tmpdir=$(_mktemp)
	pushd "${tmpdir}" > /dev/null
	fetch-repo
	check-targz
	check-zip
	popd > /dev/null
	TMPDIR="${tmpdir}" sign
	TMPDIR="${tmpdir}" verify
}

main "$@"
