#!/bin/bash
# Real desktop screenshot of Saya — RUN THIS IN YOUR OWN Terminal.app (GUI session),
# not from an agent/ssh/background shell (those have no display → screencapture fails).
#
# Needs: Screen Recording permission for Terminal (System Settings → Privacy & Security
# → Screen Recording → enable Terminal, then restart Terminal). First run will prompt.
#
# Produces:
#   docs/shot-hud.png   — desktop with the recording HUD overlay visible (auto)
#   docs/shot-menu.png   — the menu-bar dropdown (you click it; 5s countdown then capture)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

./bundle.sh >/dev/null 2>&1 || { echo "build failed"; exit 1; }
BIN="./dist/Saya.app/Contents/MacOS/Saya"
SCRATCH="$(mktemp -d)"

# Launch with the debug hook so we can toggle recording via SIGUSR1 (makes the HUD appear).
AIVI_DEBUG_DIR="$SCRATCH" "$BIN" >/dev/null 2>&1 &
APP=$!
trap 'kill $APP 2>/dev/null' EXIT
sleep 2

echo "==> Capturing the recording HUD (bottom-center overlay)…"
kill -USR1 $APP 2>/dev/null      # start recording → HUD shows
sleep 1.2
screencapture -x docs/shot-hud.png && echo "    wrote docs/shot-hud.png"
kill -USR1 $APP 2>/dev/null      # stop recording
sleep 0.5

echo ""
echo "==> Now click the 🎙️ Saya icon in the menu bar to open its dropdown."
echo "    Capturing in 5 seconds…"
for i in 5 4 3 2 1; do printf "\r    %d " "$i"; sleep 1; done; printf "\r        \n"
screencapture -x docs/shot-menu.png && echo "    wrote docs/shot-menu.png"

echo ""
echo "Done. Review docs/shot-hud.png and docs/shot-menu.png."
echo "If they look good, tell me and I'll swap them into the README (replacing the rendered preview)."
