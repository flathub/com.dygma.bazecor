#!/usr/bin/env bash

# THIS IS FOR RELEASE PURPOSES ONLY. USED FOR AUTO-UPDATING com.dygma.bazecor.yml FOR SUBMITTING A NEW RELEASE.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

tmpDownloadDir=$(mktemp -d)
trap 'rm -rf "$tmpDownloadDir"' EXIT

usage() {
	cat <<'EOF'
Usage:
  ./update.sh [--commit <COMMIT-SHA>]

Examples:
  ./update.sh --commit 7b37713f16f6e6536fe9ee4da77d9fdfca2ad862
EOF
}


download_and_extract_selected_commit() {
	local commit_sha="$1"

	asset_name="$commit_sha.tar.gz"
	asset_url="https://github.com/$REPO_OWNER/$REPO_NAME/archive/$asset_name"

	log "Downloading $asset_url into $tmpDownloadDir/$asset_name..."
	curl -fL# "$asset_url" -o "$tmpDownloadDir/$asset_name" && success || die "Failed to download $asset_name from $asset_url"
	log "Extracting $tmpDownloadDir/$asset_name..."
	tar -xzf "$tmpDownloadDir/$asset_name" -C "$tmpDownloadDir" --strip-components=1 && success || die "Failed to extract $asset_name"
}

# This function updates the Flatpak manifest file with the new commit SHA.
# Arguments:
#   $1: The new commit SHA to set in the manifest.
#
# It updates the following section in the manifest file to the selected commit SHA:
#
#     sources:
#       - type: git
#         url: "https://github.com/Dygmalab/Bazecor"
#         commit: <NEW COMMIT SHA HERE>
#
update_flatpak_manifest() {
	local commit_sha="$1"
	[ -f "$MANIFEST_FILE" ] || die "Could not find $MANIFEST_FILE"

	log "Updating $MANIFEST_FILE with commit: $commit_sha..."
	commit_sha="$commit_sha" yq eval -i '(.modules[] | select(type == "!!map" and .name == "com.dygma.bazecor") | .sources[] | select(type == "!!map" and .type == "git")) 
		|= (
			.commit = strenv(commit_sha) |
			.commit line_comment = "DO NOT MANUALLY CHANGE! Use ./update.sh instead"
		)' "$MANIFEST_FILE" && success || die "Failed to update $MANIFEST_FILE using yq."
}

# This function generates a new generated-sources.json file from the downloaded and extracted yarn.lock file.
# using the flatpak-node-generator tool.
update_generated_sources() {
	local yarn_lock_file="$tmpDownloadDir/yarn.lock"
	[ -f "$yarn_lock_file" ] || die "Yarn lock file not found: $yarn_lock_file"
	log "Regenerating generated-sources.json from $yarn_lock_file..."
	flatpak-node-generator --electron-node-headers yarn "$yarn_lock_file" && success || die "Failed to generate generated-sources.json from $yarn_lock_file"
}

main() {
	local commit_sha=""

	require_cmd appstreamcli
	require_cmd awk
	require_cmd curl
	require_cmd flatpak
	require_cmd flatpak-node-generator
	require_cmd git
	require_cmd jq
	require_cmd mktemp
	require_cmd sed
	require_cmd sha256sum
	require_cmd yq

	# Validate that the installed yq is Mike Farah's yq v4, which is required for this script to work correctly.
	yq --version | grep -q 'mikefarah/yq' || die "This script requires Mike Farah yq v4 (https://github.com/mikefarah/yq)."

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--commit)
			shift
			[ "$#" -gt 0 ] || die "Missing value after --commit"
			commit_sha="$1"
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			die "Unknown argument: $1"
			;;
		esac
		shift
	done

	if [ -z "$commit_sha" ]; then
		die "No commit specified. Please use --commit."
	fi

	cd "$(dirname "${BASH_SOURCE[0]}")"
	setup_flathub_builder
	download_and_extract_selected_commit "$commit_sha"
	update_flatpak_manifest "$commit_sha"
	update_generated_sources
	validate_flatpak_manifest "$MANIFEST_FILE"
	completed
}

main "$@"
