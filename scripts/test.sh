#!/usr/bin/env bash
# Syntax-checks every addon file and runs the headless test-suite.
set -euo pipefail
cd "$(dirname "$0")/.."
LUA=${LUA:-lua5.4}
LUAC=${LUAC:-luac5.4}
for f in $(find ForeverXP -name '*.lua' | sort); do "$LUAC" -p "$f"; done
echo "syntax ok"
"$LUA" tests/run.lua
