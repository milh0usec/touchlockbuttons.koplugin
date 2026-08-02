#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=${1:-$(tr -d '[:space:]' < VERSION)}
case "$VERSION" in
    ''|*[!0-9A-Za-z.-]*)
        echo "Invalid version: $VERSION" >&2
        exit 1
        ;;
esac

./scripts/validate.sh

DIST="$ROOT/dist"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/touchlockbuttons.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM

PLUGIN="$STAGE/touchlockbuttons.koplugin"
mkdir -p "$PLUGIN"

for path in \
    _meta.lua \
    main.lua \
    pw4-powerbutton.lua \
    pw4-powerbutton.sh \
    icons \
    VERSION \
    README.md \
    README.pt-BR.md \
    COMPATIBILITY.md \
    CHANGELOG.md \
    LICENSE \
    LICENSES \
    THIRD_PARTY_NOTICES.md; do
    cp -R "$path" "$PLUGIN/"
done

chmod 0755 "$PLUGIN/pw4-powerbutton.sh" "$PLUGIN/pw4-powerbutton.lua"
find "$PLUGIN" -type f ! -name 'pw4-powerbutton.sh' ! -name 'pw4-powerbutton.lua' -exec chmod 0644 {} +

mkdir -p "$DIST"
ARCHIVE="$DIST/touchlockbuttons.koplugin-v$VERSION.zip"
CHECKSUM="$DIST/touchlockbuttons.koplugin-v$VERSION.sha256"
rm -f "$ARCHIVE" "$CHECKSUM"

(
    cd "$STAGE"
    zip -X -q -r "$ARCHIVE" touchlockbuttons.koplugin
)

(
    cd "$DIST"
    sha256sum "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

unzip -tq "$ARCHIVE" >/dev/null
printf '%s\n' "$ARCHIVE" "$CHECKSUM"
