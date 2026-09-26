#!/bin/bash
# Export the Web build locally (needs Godot 4.7.2 + web templates). Usage: tools/export_web.sh [path-to-godot]
cd "$(dirname "$0")/.."
G="${1:-$LOCALAPPDATA/GodotTools/Godot_v4.7.2-stable_win64_console.exe}"
mkdir -p build/web && touch build/.gdignore
"$G" --headless --path . --import >/dev/null 2>&1
"$G" --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -iE "error|warn" | grep -v "Unreferenced static\|string_name" || true
cp tools/duo.html build/web/duo.html
ls -la build/web | head -20
