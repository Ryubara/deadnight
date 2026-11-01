#!/bin/bash
# Server CPU, repeated: 4 players + 24 zombies, clean link, each stack 3 times, run on a quiet machine.
# usage: tools/run_cpu.sh <godot> <out-folder>
G=$1; O=$2
cd "$(dirname "$0")/.."
cp ../net-compare-netfox/override.cfg.tuned ../net-compare-netfox/override.cfg
for rep in 1 2 3; do
  uv run --with psutil python tools/run_scenario.py --mode own --godot "$G" --out "$O" --label cpu$rep-own --seconds 16
  uv run --with psutil python tools/run_scenario.py --mode mp --godot "$G" --out "$O" --label cpu$rep-mp --seconds 16
  uv run --with psutil python tools/run_scenario.py --mode nf --extra=--tuned --project ../net-compare-netfox \
    --godot "$G" --out "$O" --label cpu$rep-nf --seconds 16
done
rm -f ../net-compare-netfox/override.cfg
