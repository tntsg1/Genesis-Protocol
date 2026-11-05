#!/usr/bin/env bash
# Run a rendering test without stealing focus or the mouse, and without
# writing anything into the project (an editor run must never pick it up):
# the window starts off-screen, and the test adds tests/test_window.gd itself
# (no-focus, click-through, parked in the corner).
# Usage: tools/run_test.sh <test.gd> [godot args] -- <args...>
cd "$(dirname "$0")/.."
script="$1"; shift
/e/godot/godot47/Godot_v4.7-stable_win64_console.exe --path . --resolution 1920x1080 --position -2600,40 -s "$script" "$@"
