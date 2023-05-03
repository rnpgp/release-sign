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

declare __PROGNAME="${0##*/}"
declare __VERSION="0.1.0"

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

cleanup() {
	if [[ -n "${TEMPDIR:-}" && -d "${TEMPDIR}" ]]
	then
		debugp "Removing tmpdir '${TEMPDIR}'"
		rm -rf "${TEMPDIR}"
	fi
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
			TEMPDIR="$base" mktemp -d -t "${tmpdir_format}"
		fi
	)
	# TEMPDIRS+=("${tmpdir}")
	echo "${tmpdir}"
}

# Print help message
print_help() {
	printf "Sign releases from the GitHub repository with PGP key.
\e[1;4mUsage\e[m
    \e[3m${__PROGNAME}\e[m \e[4mOPTIONS...\e[m \e[4m[COMMAND]\e[m

\e[1;4mExamples\e[m
    \e[3m${__PROGNAME}\e[m -r=user/repository -v=0.1.1 -k=7761E36F86C935A6
    \e[3m${__PROGNAME}\e[m -r=user/repository -v=0.1.1 verify-remote

\e[1;4mOptions\e[m
    -h, --help      - show this help message and abort
    -r, --repo      - repository, in the format \`username/repository\`
    -v, --version   - version, in the format \`x.y.z\`, without leading \`v\`
    -k, --key       - signing key id, fingerprint or email
        --gpg       - use gpg instead of rnp for signing
    -s, --src       - use specified folder for release sources
                      comparison instead of downloading from GitHub
    -t, --targz     - use specified tar.gz file for signing
    -z, --zip       - use specified zip file for signing
    -d, --debug     - dump commands which are executed
    -V, --verbose   - output progress logs
        --pparams   - all further parameters will be passed to the
                      OpenPGP backend, like:
                        '--homedir .rnp'
                        '--keyfile seckey.asc'
                        etc.

\e[1;4mCommands\e[m
    version         - display current version of ${__PROGNAME}
    verify-remote   - given \`--repo\` and \`--version\`, verify its
                      signatures + checksum hosted on the remote
                      GitHub release page
"
	echo
}

declare USEGPG=
declare REPO=
declare REPOLAST=
declare VERSION=
declare SRCDIR=
declare PPARAMS=()
declare KEY=
declare DEBUG=
declare QUIET=1
declare VERBOSE=
declare COMMAND=

OPTIND=1

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
					((OPTIND++))
					REPO="${1}"
				fi
				REPOLAST=$(basename "${REPO}")
				;;
			--version*|-v*)
				if [[ "$1" == *=* ]]; then
					VERSION="${1#*=}"
				else
					shift
					((OPTIND++))
					VERSION="${1}"
				fi
				;;
			--key*|-k*)
				if [[ "$1" == *=* ]]; then
					KEY="${1#*=}"
				else
					shift
					((OPTIND++))
					KEY="${1}"
				fi
				;;
			--gpg)
				USEGPG=1
				;;
			--zip|-z*)
				if [[ "$1" == *=* ]]; then
					ZIP="${1#*=}"
				else
					shift
					((OPTIND++))
					ZIP="${1}"
				fi

				ZIP=$(realpath "${ZIP}")

				if [[ ! -f "${ZIP}" ]]; then
					warnp "File %s doesn't exist.\n" "${ZIP}"
					exit 1
				fi
				export LOCAL_ZIP=1
				;;
			--targz|-t*)
				if [[ "$1" == *=* ]]; then
					TARGZ="${1#*=}"
				else
					shift
					((OPTIND++))
					TARGZ="${1}"
				fi

				TARGZ=$(realpath "${TARGZ}")

				if [[ ! -f "${TARGZ}" ]]; then
					warnp "File %s doesn't exist.\n" "${TARGZ}"
					exit 1
				fi
				export LOCAL_TARGZ=1
				;;
			--src*|-s*)
				if [[ "$1" == *=* ]]; then
					SRCDIR="${1#*=}"
				else
					shift
					((OPTIND++))
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
				QUIET=
				;;
			--verbose|-V)
				VERBOSE=1
				;;
			--pparams)
				shift
				((OPTIND++))
				PPARAMS=("$@")
				break
				;;
			--help|-h)
				print_help
				exit 0
				;;
			verify-remote)
				COMMAND=verify-remote
				;;
			vers*)
				echo "${__PROGNAME}  v${__VERSION}"
				exit 0
				;;
			*)
				warnp "Invalid argument: %s\nUse --help or -h to get list of available arguments.\n" "$1"
				exit 1
				;;
		esac
		shift
		((OPTIND++))
	done
}

# Check whether all parameters are specified.
validate-parameters() {
	local need_exit=
	if [[ -z "${REPO}" ]]; then
		warnp "Please specify repository via -r or --repo argument.\n"
		need_exit=1
	fi

	if [[ -z "${VERSION}" ]]; then
		warnp "Please specify release version via -v or --version argument.\n"
		need_exit=1
	fi

	if [[ -z "${KEY}" ]] && [[ "$COMMAND" != verify* ]]; then
		warnp "Signing key was not specified - so default one will be used.\n"
	fi

	if [[ -n "$need_exit" ]]; then
		exit 1
	fi
}

# Fetch repository and release tarball/zip.
fetch-repo() {
	infop "Working directory is %s\n" "$(pwd)"

	pushd "${TEMPDIR}" > /dev/null

	if [[ -z "${SRCDIR}" ]]; then
		infop "Fetching repository %s\n" "${REPO}"
		git clone \
			--branch "v${VERSION}" \
			--depth 1 \
			--recurse-submodules \
			--shallow-submodules \
			${QUIET:+--quiet} \
			"https://github.com/${REPO}"
		pushd "${REPOLAST}" > /dev/null
		infop "Checking out tag %s\n" "v${VERSION}"
		git checkout ${QUIET:+--quiet} "v${VERSION}"
		popd > /dev/null
		SRCDIR=${REPOLAST}
	fi

	popd > /dev/null
}

declare prerequisites=(
	curl
	diff
	git
	tar
	unzip
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

download-file() {
	local url="${1:?Missing URL}"
	local outfile="${2:-"${url##*/}"}"
	infop "📥 Downloading \e[1m%s\e[22m to \e[1m%s\e[22m\n" "${url}" "${outfile}"
	curl --fail -sSL "${url}" -o "${outfile}"
}

download-targz() {
	# Try downloading from release page first.
	# Failing that, download from tag page, which allows the download of
	# draft releases.
	local urls=(
		"https://github.com/${REPO}/releases/download/v${VERSION}/${TARGZ_BASEPATH}"
		"https://github.com/${REPO}/archive/refs/tags/${TARGZ_BASEPATH}"
	)
	local outfile="${TARGZ_BASEPATH}"
	for url in "${urls[@]}"; do
		if download-file "${url}" "${outfile}"
		then
			break
		fi
	done
}

download-zip() {
	local urls=(
		"https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_BASEPATH}"
		"https://github.com/${REPO}/archive/refs/tags/${ZIP_BASEPATH}"
	)
	# TODO: Support downloading draft release archives.
	# NOTE: The following 'api' url gives archive with a differently-named
	# top level directory (e.g., rnpgp-rnp-87fdd0a), thus cannot be used in
	# our signature and sum tests.
	# local url="https://api.github.com/repos/${REPO}/zipball/refs/tags/v${VERSION}"
	local outfile="${ZIP_BASEPATH}"
	for url in "${urls[@]}"; do
		if download-file "${url}" "${outfile}"
		then
			break
		fi
	done
}


# Check .tar.gz
check-targz() {
	pushd "${TEMPDIR}" > /dev/null
	if [[ -z "${LOCAL_TARGZ}" ]]; then
		download-targz
	fi
	tar xf "${TARGZ}"
	infop "Checking unpacked tarball against sources in %s\n" "$(realpath "${SRCDIR}")"
	diff -qr --exclude=".git" "${SRCDIR}" "${TARGZ_NO_EXT}"
	rm -rf "${TARGZ_NO_EXT}"
	info "✅ tarball intact"
	popd > /dev/null
}

# Check .zip
check-zip() {
	pushd "${TEMPDIR}" > /dev/null
	if [[ -z "${LOCAL_ZIP}" ]]; then
		download-zip
	fi
	unzip -qq "${ZIP}"
	infop "Checking unpacked zip archive against sources in %s\n" "$(realpath "${SRCDIR}")"
	diff -qr --exclude=".git" "${SRCDIR}" "${ZIP_NO_EXT}"
	rm -rf "${ZIP_NO_EXT}"
	info "✅ zip archive intact"
	popd > /dev/null
}

sign() {
	info "✍️ Signing tarball and zip"
	if [[ -n "${KEY}" ]]; then
		# Same for RNP and GnuPG
		PPARAMS=("-u" "${KEY}" "${PPARAMS[@]+${PPARAMS[@]}}")
	fi

	if [[ -z "${USEGPG}" ]]; then
		# Using rnp - default
		for file in "${TARGZ}" "${ZIP}"; do
			info "✍️ Signing ${file} with RNP"
			ecdo rnp --sign --detach --armor "${PPARAMS[@]+${PPARAMS[@]}}" "${file}" --output "${file##*/}.asc"
		done
	else
		# Using gpg
		for file in "${TARGZ}" "${ZIP}"; do
			info "✍️ Signing ${file} with GPG"
			ecdo gpg --armor "${PPARAMS[@]+${PPARAMS[@]}}" --output "${file##*/}.asc" --detach-sign "${file}"
		done
	fi

	# Calculate hashes as well
	info sha256sum "${ZIP_BASEPATH}" "${TARGZ_BASEPATH}" ">" "${SHA_SUM_FILE}"
	infop "🧮 Checksumming %s and %s" "${ZIP_BASEPATH}" "${TARGZ_BASEPATH}"
	sha256sum "${ZIP_BASEPATH}" "${TARGZ_BASEPATH}" > "${SHA_SUM_FILE}"

	infop "✅ Checksums are stored in files %s and %s.\n" "${TARGZ}.asc" "${ZIP}.asc";
}

verify-remote() {
	local asc_url sha_url
	for file in "${TARGZ_BASEPATH}" "${ZIP_BASEPATH}"; do
		asc_url="https://github.com/${REPO}/releases/download/v${VERSION}/${file##*/}.asc"
		download-file "$asc_url"
	done

	sha_url="https://github.com/${REPO}/releases/download/v${VERSION}/${REMOTE_SHA_SUM_FILE}"
	download-file "$sha_url"

	pushd "${TEMPDIR}" > /dev/null
	download-targz
	download-zip
	popd > /dev/null

	verify
}

verify() {
	# Validate hashes first
	for file in "${SHA_SUM_FILE}" "${TARGZ}" "${ZIP}"
	do
		if [[ ! -r "${TEMPDIR}/${file##*/}" ]]
		then
			cp "${file}" "${TEMPDIR}/"
		fi
	done
	pushd "${TEMPDIR}" > /dev/null
	ecdo sha256sum ${QUIET:+--quiet} -c "${SHA_SUM_FILE}"
	popd > /dev/null
	# Verify signatures
	if [[ -z "${USEGPG}" ]]; then
		for file in "${TARGZ}" "${ZIP}"; do
			# Work around RNP's option
			if [[ ! -r "${file##*/}" ]]; then
				cp "${file}" .
			fi
			ecdo rnp --verify "${file##*/}.asc"
			rm "${file##*/}"
		done
	else
		for file in "${TARGZ}" "${ZIP}"; do
			ecdo gpg --verify "${file##*/}.asc" "${file}"
		done
	fi
	info "✅ Signatures are verified"
}

main() {
	parse-opts "$@"
	check-prerequisites
	validate-parameters
	shift $((OPTIND - 1))

	local tmpdir
	tmpdir=$(_mktemp)
	export TEMPDIR="${tmpdir}"

	export NO_EXT_FILENAME="${NO_EXT_FILENAME:-v${VERSION}}"
	export REMOTE_NO_EXT_FILENAME="${REMOTE_NO_EXT_FILENAME:-${NO_EXT_FILENAME}}"

	export TARGZ="${TARGZ:-${NO_EXT_FILENAME}.tar.gz}"
	export TARGZ_BASEPATH="${TARGZ##*/}"
	export ZIP="${ZIP:-${NO_EXT_FILENAME}.zip}"
	export ZIP_BASEPATH="${ZIP##*/}"

	TARGZ_NO_EXT="${TARGZ_NO_EXT:-${TARGZ##*/}}"
	TARGZ_NO_EXT="${TARGZ_NO_EXT%.tar.gz}"
	TARGZ_NO_EXT="${TARGZ_NO_EXT%.tgz}"
	export TARGZ_NO_EXT

	ZIP_NO_EXT="${ZIP_NO_EXT:-${ZIP##*/}}"
	ZIP_NO_EXT="${ZIP_NO_EXT%.*}"
	export ZIP_NO_EXT

	export SHA_SUM_FILE="${SHA_SUM_FILE:-${ZIP_BASEPATH%.*}.sha256}"
	export REMOTE_SHA_SUM_FILE="${REMOTE_SHA_SUM_FILE:-${SHA_SUM_FILE}}"

	if [[ -n "$COMMAND" ]]; then
		"$COMMAND"
	else
		warnp "Using zip file from %s\n" "${ZIP}"
		warnp "Using tar.gz file from %s\n" "${TARGZ}"
		fetch-repo
		check-targz
		check-zip
		sign
		verify
	fi
}

main "$@"
