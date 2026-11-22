#!/bin/bash
# Builds the web engine for wasm32-wasip1 into web/engine/out with the FPC
# trunk cross-compiler (see README.md): out/engine_serve.wasm for Node, and
# out/browser/engine_lib.wasm for the page in browser/. FPC_WASM is the installed compiler's
# lib/fpc/<version> folder; extra arguments go to the compiler.
set -e
FPC_WASM="${FPC_WASM:-$HOME/Packages/fpc-wasm/install/lib/fpc/3.3.1}"
COMPILER="$FPC_WASM/ppcrosswasm32"
UNITS="$FPC_WASM/units/wasm32-wasip1"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CLIPPER="$ROOT/src/packages/clipper2/Delphi/Clipper2Lib"
if [ ! -x "$COMPILER" ]; then
  echo "No wasm32 cross-compiler at $COMPILER; see web/engine/README.md, or set FPC_WASM" >&2
  exit 2
fi
PACKAGE_UNITS=()
for folder in "$UNITS"/*/; do PACKAGE_UNITS+=("-Fu$folder"); done
mkdir -p "$HERE/out"
cd "$HERE"
# -n: not the system fpc.cfg, which is the desktop compiler's. The stubs come
# before src/output, and src/output/thirdparty is left out.
compile() {
  "$COMPILER" -n -Twasip1 -Pwasm32 -MObjFPC -Sh -FcUTF8 -O2 -Xs -XX -CX -vewn \
    -Fustubs -Fu"$ROOT/src/core" -Fu"$ROOT/src/document" -Fu"$ROOT/src/api" -Fu"$ROOT/src/output" \
    -Fu"$CLIPPER" -Fi"$CLIPPER" "${PACKAGE_UNITS[@]}" -FUout -FEout "${EXTRA[@]}" "$1"
}
EXTRA=("$@")
# The WASI program for Node, and the library the browser page loads
compile engine_serve.lpr
compile engine_lib.lpr
mkdir -p out/browser
cp out/engine_lib out/browser/engine_lib.wasm
