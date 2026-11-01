#!/bin/bash
# Runs the whole comparison: clean, 100 ms RTT, 100 ms RTT + 2% TCP loss, for both stacks.
# usage: tools/run_all.sh <godot> <out-folder> [seconds]
G=$1; O=$2; S=${3:-24}
cd "$(dirname "$0")/.."
for scenario in "clean 0 0" "rtt100 50 0" "rtt100-loss2 50 0.02"; do
  set -- $scenario
  for mode in own mp; do
    uv run --with psutil python tools/run_scenario.py --mode $mode --godot "$G" --out "$O" \
      --label "$mode-$1" --latency-ms $2 --loss $3 --seconds $S
    echo
  done
done
