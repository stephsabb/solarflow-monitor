#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
owner="${GITHUB_OWNER:?Définissez GITHUB_OWNER}"
repository="${GITHUB_REPOSITORY:?Définissez GITHUB_REPOSITORY}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/work/Info.plist")
archive="$project_dir/outputs/SolarFlow-Monitor-App.zip"
"$project_dir/Scripts/build-release.sh"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait; fi
gh release create "v$version" "$archive#SolarFlow-Monitor-App.zip" --repo "$owner/$repository" --title "SolarFlow Monitor $version" --generate-notes
"$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" --download-url-prefix "https://github.com/$owner/$repository/releases/download/v$version/" --link "https://$owner.github.io/$repository/" -o "$project_dir/docs/appcast.xml" "$project_dir/outputs"
echo "Release publiée. Catalogue : https://$owner.github.io/$repository/appcast.xml"
