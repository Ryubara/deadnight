#!/bin/bash
# Bandwidth and CPU against player count, clean link, 24 zombies, for the own protocol and three
# built-in MultiplayerAPI setups (server-owned, server-owned with a packed position, client-owned).
# usage: tools/run_scaling.sh <godot> <out-folder> [seconds]
G=$1; O=$2; S=${3:-16}
cd "$(dirname "$0")/.."
for n in 2 4 8; do
  for setup in "own " "mp " "mp-pack --pack" "mp-clientauth --client-auth"; do
    set -- $setup
    mode=${1%%-*}
    uv run --with psutil python tools/run_scenario.py --mode $mode --godot "$G" --out "$O" \
      --label "scale$n-$1" --players $n --seconds $S ${2:+--extra=$2}
    echo
  done
done
