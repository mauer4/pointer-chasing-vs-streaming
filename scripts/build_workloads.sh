#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"

mkdir -p "$BIN_DIR"

cc -O2 -std=c11 -Wall -Wextra -pedantic -o "$BIN_DIR/array_add" "$ROOT_DIR/src/array_add.c"
cc -O2 -std=c11 -Wall -Wextra -pedantic -o "$BIN_DIR/list_add" "$ROOT_DIR/src/list_add.c"
cc -O2 -std=c11 -Wall -Wextra -pedantic -o "$BIN_DIR/array_add_stack" "$ROOT_DIR/src/array_add_stack.c"
cc -O2 -std=c11 -Wall -Wextra -pedantic -o "$BIN_DIR/list_add_stack" "$ROOT_DIR/src/list_add_stack.c"

echo "[build] built: $BIN_DIR/array_add"
echo "[build] built: $BIN_DIR/list_add"
echo "[build] built: $BIN_DIR/array_add_stack"
echo "[build] built: $BIN_DIR/list_add_stack"
