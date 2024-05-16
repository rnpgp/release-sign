#!/usr/bin/env bash


# The default fingerprint for tags that are not tested explicitly in this file:
KEY_1_FPR=A845A5BD622556E89D7763B5EB06D1696BEC4C90
KEY_2_FPR=50DA59D5B9134FA2DB1EB20CFB829AB5D0FE017F
# KEY_3_FPR=???????????????????????????????????????? # TODO: future keys are listed here
DEFAULT_FPR="${KEY_2_FPR:?}" # TODO: the latest key shall become the default

# Populate array with all tags from remote
all_tags=()

while read -r tag
do
	all_tags+=("$tag")
done < <(
	git ls-remote --tags https://github.com/rnpgp/rnp | \
	sed '/tags/!d; /{}$/d; s@^.*refs/tags/v@@' | \
	# Process latest tags first
	sort --version-sort -r
)

expected-archive-name-for-version() {
	local version="${1:?Missing version}"
	case "${version}" in
		0.17.*)
			echo "rnp-v${version}"
			;;
		*)
			echo "v${version}"
			;;
	esac
}

expected-signature-for-version() {
	local version="${1:?Missing version}"
	case "${version}" in
		0.9.*|0.1[012345].[012]|0.16.0)
			debug "Using ${KEY_1_FPR} for version ${version}."
			echo "${KEY_1_FPR}"
			;;
		0.1[67].*)
			debug "Using ${KEY_2_FPR} for version ${version}."
			echo "${KEY_2_FPR}"
			;;
		# TODO: Insert future expectations here
		# 1.*.*)
		# 	echo "${KEY_3_FPR}"
		# 	;;
		*)
			warn "Version (${version}) not matched.  Using ${DEFAULT_FPR}."
			echo "${DEFAULT_FPR}"
	esac
}

expected-zip-and-or-tar-for-version() {
	local version="${1:?Missing version}"
	case "${version}" in
		0.9.*|0.1[012345].[012]|0.16.[0123]|0.17.0)
			echo "zt"
			;;
		0.17.1)
			echo "t"
			;;
		*)
			warn "Version (${version}) not matched.  Checking tarball only."
			echo "t"

			;;
	esac
}

for version in "${all_tags[@]}"
do
	test_package_signature \
		"${version}" \
		"$(expected-signature-for-version "${version}")" \
		"$(expected-archive-name-for-version "${version}")" \
		"$(expected-zip-and-or-tar-for-version "${version}")"
done
