#!/usr/bin/env bash


# The default fingerprint for tags that are not tested explicitly in this file:
KEY_1_FPR=A845A5BD622556E89D7763B5EB06D1696BEC4C90
# KEY_2_FPR=???????????????????????????????????????? # TODO: future keys are listed here
DEFAULT_FPR="${KEY_1_FPR:?}" # TODO: the latest key shall become the default

# Populate array with all tags from remote
all_tags=()

while read -r tag
do
	all_tags+=("$tag")
done < <(git ls-remote --tags https://github.com/rnpgp/rnp | sed '/tags/!d; /{}$/d; s@^.*refs/tags/v@@')

expected-signature-for-version() {
	local version="${1:?Missing version}"
	case "${version}" in
		0.9.*|0.1{0..5}.{0..2})
			echo "${KEY_1_FPR}"
			;;
		# TODO: Insert future expectations here
		# 1.*.*)
		# 	echo "${KEY_2_FPR}"
		# 	;;
		*)
			echo "${DEFAULT_FPR}"
	esac
}

for version in "${all_tags[@]}"
do
	test_package_signature "${version}" "$(expected-signature-for-version "${version}")"
done
