#!/bin/bash
# Fetches netfox (MIT, pinned tag) into addons/ and copies the shared scripts from ../net-compare.
# Neither is committed: the addon is third-party, the scripts are copies of the other project's.
# usage: tools/setup_netfox.sh [path to an existing netfox checkout]
set -e
cd "$(dirname "$0")/.."
TAG=${NETFOX_TAG:-v1.35.3}
SRC=${1:-$(mktemp -d)/netfox}
[ -d "$SRC" ] || git clone -q --depth 1 --branch "$TAG" https://github.com/foxssake/netfox.git "$SRC"
mkdir -p addons scripts/shared
for a in netfox netfox.extras netfox.internals; do
  rm -rf "addons/$a"
  cp -r "$SRC/addons/$a" addons/
done
cp ../net-compare/scripts/sim/game_sim.gd ../net-compare/scripts/sim/input_sampler.gd \
  ../net-compare/scripts/client_stats.gd ../net-compare/scripts/net_args.gd scripts/shared/
echo "netfox ready"
