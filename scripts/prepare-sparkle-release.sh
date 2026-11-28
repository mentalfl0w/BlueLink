#!/usr/bin/env bash
# Generates and validates the signed Sparkle appcast for a stable BlueLink release.
# Usage: prepare-sparkle-release.sh <release-assets-dir> <output-dir> <tag> <version> <build-number>
set -euo pipefail
set +x

if [[ $# -ne 5 ]]; then
    echo "Usage: prepare-sparkle-release.sh <release-assets-dir> <output-dir> <tag> <version> <build-number>" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_assets_dir="$1"
output_dir="$2"
tag="$3"
version="$4"
build_number="$5"
archive_name="BlueLink-${version}-${build_number}.zip"
archive_path="$release_assets_dir/$archive_name"
expected_public_key="ZA+az1CkNnvjCM1YKobsrnREcJWED5smqyNdMXxzZZc="
private_key_base64="${SPARKLE_EDDSA_PRIVATE_KEY_BASE64:-}"
unset SPARKLE_EDDSA_PRIVATE_KEY_BASE64
private_key_base64="$(printf '%s' "$private_key_base64" | tr -d '[:space:]')"

if [[ -z "$private_key_base64" ]]; then
    echo "Sparkle releases require SPARKLE_EDDSA_PRIVATE_KEY_BASE64." >&2
    exit 1
fi
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Sparkle releases require a stable tag of the form vMAJOR.MINOR.PATCH." >&2
    exit 1
fi
if [[ "$tag" != "v$version" ]]; then
    echo "Release tag must be exactly v<bundle version>." >&2
    exit 1
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must be a positive integer." >&2
    exit 1
fi
if [[ ! -s "$archive_path" ]]; then
    echo "Expected Sparkle archive is missing: $archive_name" >&2
    exit 1
fi
if [[ -e "$output_dir/appcast.xml" ]]; then
    echo "Refusing to overwrite an existing appcast output." >&2
    exit 1
fi

scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/bluelink-sparkle-release.XXXXXX")"
chmod 700 "$scratch_dir"
cleanup() {
    rm -rf "$scratch_dir"
}
trap cleanup EXIT

if ! printf '%s' "$private_key_base64" |
    python3 -c 'import base64,sys; data=base64.b64decode(sys.stdin.buffer.read(), validate=True); assert len(data)==32' \
        >/dev/null 2>&1; then
    echo "Sparkle private-key secret is not a valid 32-byte base64 EdDSA key." >&2
    exit 1
fi

unpack_dir="$scratch_dir/unpacked"
mkdir -p "$unpack_dir"
ditto -x -k "$archive_path" "$unpack_dir"
app_path="$unpack_dir/BlueLink.app"
if [[ ! -d "$app_path" ]]; then
    echo "Sparkle archive does not contain the expected BlueLink.app bundle." >&2
    exit 1
fi
info_plist="$app_path/Contents/Info.plist"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
bundle_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist")"
bundle_feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist")"
require_signed_feed="$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$info_plist" | tr '[:upper:]' '[:lower:]')"
verify_before_extract="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$info_plist" | tr '[:upper:]' '[:lower:]')"

if [[ "$bundle_version" != "$version" || "$bundle_build" != "$build_number" ]]; then
    echo "Release metadata does not match the app bundle version/build." >&2
    exit 1
fi
if [[ "$bundle_public_key" != "$expected_public_key" ]]; then
    echo "Embedded Sparkle public key does not match the BlueLink signing key." >&2
    exit 1
fi
if [[ "$bundle_feed_url" != "https://github.com/mentalfl0w/BlueLink/releases/latest/download/appcast.xml" ]]; then
    echo "App bundle does not contain the stable HTTPS GitHub Sparkle feed URL." >&2
    exit 1
fi
if [[ "$require_signed_feed" != "true" && "$require_signed_feed" != "yes" && "$require_signed_feed" != "1" ]]; then
    echo "App bundle does not require signed Sparkle feeds." >&2
    exit 1
fi
if [[ "$verify_before_extract" != "true" && "$verify_before_extract" != "yes" && "$verify_before_extract" != "1" ]]; then
    echo "App bundle does not verify signed updates before extraction." >&2
    exit 1
fi

sparkle_version="2.10.1"
sparkle_download="https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz"
expected_sparkle_sha256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
toolchain_dir="$scratch_dir/toolchain"
sparkle_archive="$scratch_dir/sparkle-tools.tar.xz"
mkdir -p "$toolchain_dir"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$sparkle_archive" "$sparkle_download"
actual_sparkle_sha256="$(shasum -a 256 "$sparkle_archive" | awk '{print $1}')"
if [[ "$actual_sparkle_sha256" != "$expected_sparkle_sha256" ]]; then
    echo "Downloaded Sparkle 2.10.1 tool archive failed the pinned SHA-256 check." >&2
    exit 1
fi
tar -xJf "$sparkle_archive" -C "$toolchain_dir"
generate_appcast="$toolchain_dir/bin/generate_appcast"
if [[ ! -x "$generate_appcast" ]]; then
    echo "Sparkle 2.10.1 appcast tool is missing from the verified official distribution." >&2
    exit 1
fi

update_input="$scratch_dir/update-input"
mkdir -p "$update_input"
cp "$archive_path" "$update_input/$archive_name"
private_key_file="$scratch_dir/private.edKey"
printf '%s\n' "$private_key_base64" > "$private_key_file"
chmod 600 "$private_key_file"
unset private_key_base64
mkdir -p "$output_dir"
appcast_path="$output_dir/appcast.xml"
release_notes_url="https://github.com/mentalfl0w/BlueLink/releases/tag/$tag"
if ! "$generate_appcast" \
    --ed-key-file "$private_key_file" \
    --download-url-prefix "https://github.com/mentalfl0w/BlueLink/releases/download/$tag/" \
    --full-release-notes-url "$release_notes_url" \
    -o "$appcast_path" \
    "$update_input" >"$scratch_dir/appcast-generation.log" 2>&1; then
    echo "Sparkle failed to generate the signed appcast and update signature." >&2
    exit 1
fi
swift "$repo_root/scripts/verify-sparkle-appcast.swift" "$appcast_path" "$expected_public_key"
python3 "$repo_root/scripts/sparkle_release.py" \
    --path "$appcast_path" \
    --tag "$tag" \
    --version "$version" \
    --build-number "$build_number" \
    --archive-name "$archive_name"
echo "Prepared and validated the signed Sparkle appcast for $tag (build $build_number)."
