#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p /tmp/sellaris-checks
check() {
  local label="$1"
  shift
  local log="/tmp/sellaris-checks/${label}.log"
  if ! timeout 120 "$GODOT_BIN" --headless --path . "$@" >"$log" 2>&1; then
    cat "$log"
    return 1
  fi
  cat "$log"
  if grep -Eq 'SCRIPT ERROR|Parse Error|Shader compilation failed|Assertion failed' "$log"; then
    return 1
  fi
}
check import --editor --import
check lobby --script res://tests/lobby_state_test.gd
check visuals --script res://tests/observatory_visual_test.gd
check deterministic --script res://tests/celestial_visual_determinism_test.gd
check builder res://tests/builder_ship_smoke_test.tscn
check station_cost res://tests/station_cost_boundary_test.tscn
check ships res://tests/ship_set_smoke_test.tscn
check research res://tests/research_modal_smoke_test.tscn
check drawer --script res://tests/empire_command_drawer_smoke_test.gd
check menu --quit-after 12
check host res://tests/network_lobby_smoke_test.tscn -- --lobby-host &
host_pid=$!
trap 'kill "$host_pid" 2>/dev/null || true' EXIT
sleep 1
check client res://tests/network_lobby_smoke_test.tscn
wait "$host_pid"
trap - EXIT
