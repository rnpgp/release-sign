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

declare __BIN="$(command realpath "${BASH_SOURCE[0]}")"
declare __ROOTDIR="$(command cd "${__BIN%/*}" > /dev/null && pwd -P)"
declare __VERSION_FILE="${__ROOTDIR}/VERSION"
declare __VERSION="$( [[ -r "${__VERSION_FILE}" ]] && cat "${__VERSION_FILE}" || echo " git-dev" )"

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

declare EXPLICIT_ARCHIVE_SPECIFIED=
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
				EXPLICIT_ARCHIVE_SPECIFIED=1

				if [[ "$1" == *=* ]]; then
					ZIP="${1#*=}"
				else
					shift
					((OPTIND++))
					ZIP="${1}"
				fi
				;;
			--targz|-t*)
				EXPLICIT_ARCHIVE_SPECIFIED=1

				if [[ "$1" == *=* ]]; then
					TARGZ="${1#*=}"
				else
					shift
					((OPTIND++))
					TARGZ="${1}"
				fi
				;;
			--src*|-s*)
				if [[ "$1" == *=* ]]; then
					SRCDIR="${1#*=}"
				else
					shift
					((OPTIND++))
					SRCDIR="${1}"
				fi
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
	else
		export NO_EXT_FILENAME="${NO_EXT_FILENAME:-v${VERSION}}"
		export REMOTE_NO_EXT_FILENAME="${REMOTE_NO_EXT_FILENAME:-${NO_EXT_FILENAME}}"
	fi

	if [[ -z "${KEY}" ]] && [[ "$COMMAND" != verify* ]]; then
		warnp "Signing key was not specified - so default one will be used.\n"
	fi

	if [[ "${COMMAND:-}" != verify-remote ]]; then
		if [[ -n "${ZIP:-}" ]]; then
			ZIP=$(realpath "${ZIP}")

			if [[ ! -f "${ZIP}" ]]; then
				warnp "File %s doesn't exist.\n" "${ZIP}"
				need_exit=1
			fi
			export LOCAL_ZIP=1
		fi

		if [[ -n "${TARGZ:-}" ]]; then
			TARGZ=$(realpath "${TARGZ}")

			if [[ ! -f "${TARGZ}" ]]; then
				warnp "File %s doesn't exist.\n" "${TARGZ}"
				need_exit=1
			fi
			export LOCAL_TARGZ=1
		fi
	fi


	if [[ -n "${SRCDIR:-}" ]]; then
		SRCDIR=$(realpath "${SRCDIR}")

		if [[ ! -d "${SRCDIR}" ]]; then
			warnp "Directory %s doesn't exist.\n" "${SRCDIR}"
			need_exit=1
		fi

		warnp "Comparing with sources from %s\n" "${SRCDIR}"
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

download-urls() {
	local outfile="${1:?Missing outfile}"; shift
	local failed_to_download_anything=1

	for url in "$@"; do
		if download-file "${url}" "${outfile}"
		then
			failed_to_download_anything=
			break
		fi
	done

	if [[ -n "${failed_to_download_anything}" ]]
	then
		warnp "Failed to download any of the following URLs: %s\n" "$*"
	fi
}

download-github-archives() {
	local archive_basepath="${1:?Missing archive basepath}"

	# Try downloading from release page first.
	# Failing that, download from tag page, which allows the download of
	# draft releases.
	local urls=(
		"https://github.com/${REPO}/releases/download/v${VERSION}/${archive_basepath}"
		"https://github.com/${REPO}/archive/refs/tags/${archive_basepath}"
	)
	# TODO: Support downloading draft release archives.
	# NOTE: The following 'api' url gives archive with a differently-named
	# top level directory (e.g., rnpgp-rnp-87fdd0a), thus cannot be used in
	# our signature and sum tests.
	# local url="https://api.github.com/repos/${REPO}/zipball/refs/tags/v${VERSION}"
	local outfile="${archive_basepath}"
	download-urls "${outfile}" "${urls[@]}"
}

download-targz() {
	download-github-archives "${TARGZ_BASEPATH}"
}

download-zip() {
	download-github-archives "${ZIP_BASEPATH}"
}

# A list of globs to exclude when diffing between source archives and git
# source tree.
declare DIFF_EXCLUDES=(
	.cirrus.yml
	.clang-format
	.codespellrc
	.config.yml
	.editorconfig
	.git
	.gitattributes
	.github
	.gitignore
	.gitmodules
	_config.yml
	ci
	ci-legacy
	codecov.yml
	git-hooks
	src/libsexpp/.clangformat
	src/libsexpp/.git
	src/libsexpp/.gitattributes
	src/libsexpp/.github
	src/libsexpp/.gitignore
	src/libsexpp/codecov.yml
)

# Diff between SRCDIR and expanded archives
diff-exclude-globs() {
	for pattern in "$@"
	do
		exclude_globs+=("-x ${pattern}")
	done
}

diff-it() {
	local srcdir="${1:?Missing srcdir}"
	local expanded="${2:?Missing path of expanded archive}"
	local exclude_globs=()
	diff-exclude-globs "${DIFF_EXCLUDES[@]}"

	ecdo diff -qr ${exclude_globs:+${exclude_globs[@]}} "${srcdir}" "${expanded}"
}


# Check .tar.gz
check-targz() {
	pushd "${TEMPDIR}" > /dev/null
	if [[ -z "${LOCAL_TARGZ:-}" ]]; then
		download-targz
	fi
	tar xf "${TARGZ}"
	infop "Checking unpacked tarball against sources in %s\n" "${SRCDIR}"
	diff-it "${SRCDIR}" "${EXPANDED_TARGZ}"
	rm -rf "${EXPANDED_TARGZ}"
	info "✅ tarball intact"
	popd > /dev/null
}

# Check .zip
check-zip() {
	pushd "${TEMPDIR}" > /dev/null
	if [[ -z "${LOCAL_ZIP:-}" ]]; then
		download-zip
	fi
	unzip -qq "${ZIP}"
	infop "Checking unpacked zip archive against sources in %s\n" "${SRCDIR}"
	diff-it "${SRCDIR}" "${EXPANDED_ZIP}"
	rm -rf "${EXPANDED_ZIP}"
	info "✅ zip archive intact"
	popd > /dev/null
}

sign() {
	info "✍️ Signing: ${*}"
	if [[ -n "${KEY}" ]]; then
		# Same for RNP and GnuPG
		PPARAMS=("-u" "${KEY}" "${PPARAMS[@]+${PPARAMS[@]}}")
	fi

	for file in "$@"
	do
		if [[ ! -r "${TEMPDIR}/${file##*/}" ]]
		then
			cp "${file}" "${TEMPDIR}/"
		fi
	done
	pushd "${TEMPDIR}" > /dev/null

	if [[ -z "${USEGPG}" ]]; then
		# Using rnp - default
		for file in "$@"; do
			info "✍️ Signing ${file} with RNP"
			ecdo rnp --sign --detach --armor "${PPARAMS[@]+${PPARAMS[@]}}" "${file}" --output "${file##*/}.asc"
		done
	else
		# Using gpg
		for file in "$@"; do
			info "✍️ Signing ${file} with GPG"
			ecdo gpg --armor "${PPARAMS[@]+${PPARAMS[@]}}" --output "${file##*/}.asc" --detach-sign "${file}"
		done
	fi

	# Calculate hashes as well
	base_paths=()
	for file in "$@"; do
		base_paths+=("${file##*/}")
	done

	info sha256sum "${base_paths[@]}" ">" "${SHA_SUM_FILE}"
	infop "🧮 Checksumming %s\n" "${base_paths[@]}"
	sha256sum "${base_paths[@]}" > "${SHA_SUM_FILE}"
	popd > /dev/null

	artifact_paths=("${SHA_SUM_FILE##*/}" "${base_paths[@]/%/.asc}")
	artifact_paths=("${artifact_paths[@]/#/${TEMPDIR}/}")
	infop "📦 Artifact: %s\n" "${artifact_paths[@]}"

	for file in "${artifact_paths[@]}"
	do
		mv "${file}" .
	done

	infop "✅ Checksums are stored in files %s.\n" "${@/%/.asc}"
}

verify-remote() {
	local asc_url sha_url

	pushd "${TEMPDIR}" > /dev/null
	for file in "${TARGZ_BASEPATH}" "${ZIP_BASEPATH}"; do
		asc_url="https://github.com/${REPO}/releases/download/v${VERSION}/${file##*/}.asc"
		download-file "$asc_url"
	done

	sha_url="https://github.com/${REPO}/releases/download/v${VERSION}/${REMOTE_SHA_SUM_FILE}"

	download-file "$sha_url"
	download-targz
	download-zip
	verify "${REMOTE_SHA_SUM_FILE}" "${TARGZ_BASEPATH}" "${ZIP_BASEPATH}"
	popd > /dev/null

}

verify() {
	local sha_sum_file="$1"; shift

	# Validate hashes first
	for file in "${sha_sum_file}" "$@" "${@/%/.asc}"
	do
		if [[ ! -r "${TEMPDIR}/${file##*/}" ]]
		then
			cp "${file}" "${TEMPDIR}/"
		fi
	done

	pushd "${TEMPDIR}" > /dev/null
	ecdo sha256sum ${QUIET:+--quiet} -c "${sha_sum_file}"

	# Verify signatures
	if [[ -z "${USEGPG:-}" ]]; then
		for file in "$@"; do
			# Work around RNP's option
			if [[ ! -r "${file##*/}" ]]; then
				cp "${file}" .
			fi
			ecdo rnp --verify "${file##*/}.asc"
			rm "${file##*/}"
		done
	else
		for file in "$@"; do
			ecdo gpg --verify "${file##*/}.asc" "${file}"
		done
	fi
	popd > /dev/null
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

	# If local targz/zip, must use explicit parameters
	if [[ -z "${EXPLICIT_ARCHIVE_SPECIFIED:-}" ]]; then
		export TARGZ="${TARGZ:-${NO_EXT_FILENAME}.tar.gz}"
		export ZIP="${ZIP:-${NO_EXT_FILENAME}.zip}"
	fi

	export TARGZ_BASEPATH="${TARGZ##*/}"
	export ZIP_BASEPATH="${ZIP##*/}"

	TARGZ_NO_EXT="${TARGZ_NO_EXT:-${TARGZ_BASEPATH}}"
	TARGZ_NO_EXT="${TARGZ_NO_EXT%.tar.gz}"
	TARGZ_NO_EXT="${TARGZ_NO_EXT%.tgz}"
	export TARGZ_NO_EXT

	ZIP_NO_EXT="${ZIP_NO_EXT:-${ZIP##*/}}"
	ZIP_NO_EXT="${ZIP_NO_EXT%.*}"
	export ZIP_NO_EXT

	export DEFAULT_EXPANDED_PATH="${REPOLAST}-${VERSION}"

	# Choose a name for the expanded targz file
	if [[ -z "${LOCAL_ZIP:-}" ]]; then
		export EXPANDED_ZIP="${DEFAULT_EXPANDED_PATH}"
	else
		export EXPANDED_ZIP="${ZIP_NO_EXT}"
	fi

	# Choose a name for the expanded targz file
	if [[ -z "${LOCAL_TARGZ:-}" ]]; then
		export EXPANDED_TARGZ="${DEFAULT_EXPANDED_PATH}"
	else
		export EXPANDED_TARGZ="${TARGZ_NO_EXT}"
	fi

	# Choose a name for the checksum file
	if [[ -n "${ZIP_BASEPATH:-}" ]]; then
		export SHA_SUM_FILE="${SHA_SUM_FILE:-${ZIP_BASEPATH%.*}.sha256}"
	else
		export SHA_SUM_FILE="${SHA_SUM_FILE:-${TARGZ_BASEPATH%.tar.gz}.sha256}"
	fi

	export REMOTE_SHA_SUM_FILE="${REMOTE_SHA_SUM_FILE:-${SHA_SUM_FILE}}"

	if [[ -n "$COMMAND" ]]; then
		"$COMMAND"
	else
		fetch-repo

		FILES_TO_CHECK=()

		if [[ -n "${TARGZ:-}" ]]; then
			warnp "Using tar.gz file from %s\n" "${TARGZ}"
			FILES_TO_CHECK+=("${TARGZ}")
			check-targz
		fi

		if [[ -n "${ZIP:-}" ]]; then
			warnp "Using zip file from %s\n" "${ZIP}"
			FILES_TO_CHECK+=("${ZIP}")
			check-zip
		fi

		sign "${FILES_TO_CHECK[@]}"
		verify "${SHA_SUM_FILE}" "${FILES_TO_CHECK[@]}"
	fi
}

main "$@"
