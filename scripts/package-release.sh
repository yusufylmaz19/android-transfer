#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

tag="${1:-v0.2.0-beta.1}"
if [[ ! "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$' ]]; then
  echo "Geçersiz sürüm etiketi: $tag" >&2
  exit 1
fi

app="dist/AndroidTransfer.app"
apk="mobile/build/app/outputs/flutter-apk/app-release.apk"
[[ -d "$app" && -f "$apk" ]] || { echo "Önce Mac uygulamasını ve evrensel Android APK'sını derleyin." >&2; exit 1; }

output="dist/release-$tag"
mkdir -p "$output"
zip="$output/AndroidTransfer-mac-$tag.zip"
release_apk="$output/AndroidTransfer-android-$tag.apk"
ditto -c -k --keepParent "$app" "$zip"
cp "$apk" "$release_apk"
(cd "$output" && shasum -a 256 "${zip:t}" "${release_apk:t}" > SHA256SUMS.txt)
echo "Hazır: $output"
