#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

required_files="
_meta.lua
main.lua
pw4-powerbutton.lua
pw4-powerbutton.sh
VERSION
README.md
README.pt-BR.md
COMPATIBILITY.md
CHANGELOG.md
LICENSE
THIRD_PARTY_NOTICES.md
LICENSES/OFL-1.1.txt
icons/touchlockbuttons-fa-lock.svg
icons/touchlockbuttons-fa-unlock.svg
icons/touchlockbuttons-fa-toggle-on.svg
icons/touchlockbuttons-fa-toggle-off.svg
icons/touchlockbuttons-fa-moon-o.svg
scripts/check_lua_syntax.lua
"

for file in $required_files; do
    if [ ! -f "$file" ]; then
        echo "Missing required file: $file" >&2
        exit 1
    fi
done

if grep -Eq '^[[:space:]]*name[[:space:]]*=' _meta.lua; then
    echo "_meta.lua still contains the deprecated name field." >&2
    exit 1
fi

if ! grep -q 'name = "touchlockbuttons"' main.lua; then
    echo "Plugin runtime name is missing or unexpected." >&2
    exit 1
fi

sh -n pw4-powerbutton.sh
sh -n scripts/package.sh

LUA_COMPILER=""
for candidate in luac5.1 luac texlua lua5.1 lua; do
    if command -v "$candidate" >/dev/null 2>&1; then
        LUA_COMPILER=$candidate
        break
    fi
done

if [ -n "$LUA_COMPILER" ]; then
    case "$LUA_COMPILER" in
        luac5.1|luac)
            "$LUA_COMPILER" -p main.lua _meta.lua pw4-powerbutton.lua
            ;;
        *)
            "$LUA_COMPILER" scripts/check_lua_syntax.lua \
                main.lua _meta.lua pw4-powerbutton.lua
            ;;
    esac
else
    echo "Warning: no Lua parser found; skipping Lua syntax check." >&2
fi

python3 - <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

root = Path('.')
for path in sorted((root / 'icons').glob('*.svg')):
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise SystemExit(f'Invalid SVG {path}: {exc}')
    tag = tree.getroot().tag
    if not tag.endswith('svg'):
        raise SystemExit(f'Unexpected root element in {path}: {tag}')

for path in root.rglob('*'):
    if path.is_file() and path.suffix.lower() in {'.lua', '.sh', '.svg', '.md', '.txt', ''}:
        data = path.read_bytes()
        if b'\r\n' in data:
            raise SystemExit(f'CRLF line endings found: {path}')

for forbidden in ['.DS_Store', 'Thumbs.db']:
    if any(p.name == forbidden for p in root.rglob('*')):
        raise SystemExit(f'Forbidden generated file found: {forbidden}')
PY

for icon in lock unlock toggle-on toggle-off moon-o; do
    grep -q "touchlockbuttons-fa-$icon" main.lua || {
        echo "Icon is packaged but not referenced: $icon" >&2
        exit 1
    }
done

echo "Validation passed."
