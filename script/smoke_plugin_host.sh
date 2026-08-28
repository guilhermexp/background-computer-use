#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST_BINARY="$REPO_DIR/.build/plugin-host-smoke"
PLUGIN_BINARY="$REPO_DIR/dist/BCUAuthorizationPlugin.bundle/Contents/MacOS/BCUAuthorizationPlugin"

cd "$REPO_DIR"
script/build_locked_use.sh
xcrun clang -Wall -Wextra -Werror -framework Security -ldl \
  script/plugin_host_smoke.c -o "$HOST_BINARY"
"$HOST_BINARY" "$PLUGIN_BINARY"
