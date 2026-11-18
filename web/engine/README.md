# Web engine (spike)

The OpenSloper engine (`src/core`, `src/document`, `src/api` and `src/output`,
with Clipper2) compiled to WebAssembly for `wasm32-wasip1`, as planned under
Web version in `documents/opensloper-design-document.md`, whose Spike results
say what it showed. For now it is a WASI program that answers Automation API
requests, one JSON-RPC message a line on standard input and one reply a line
on standard output, as `opensloper-cli serve` does. A browser build with an
exported `handle()` comes next.

| File | What it is |
| --- | --- |
| `engine_serve.lpr` | The program: `TApiServer` over stdin and stdout |
| `stubs/` | Stand-ins for `Sloper.Output.DraftPNG` and `Sloper.Output.GarmentPNG` with the same interface, without BGRABitmap; PNG is refused |
| `build.sh` | Builds `out/engine_serve.wasm` |
| `run.mjs` | Runs it under Node's WASI, with a folder mounted as `/data` |
| `compare.py` | Runs every regression case through the desktop CLI and the engine, and compares the answers |
| `fpc-wasi-fexpand.patch` | The fix to FPC trunk's WASI `ExpandFileName` the engine needs |

## The compiler

The Wasm target is only in FPC trunk (3.3.1), so the cross-compiler is built
from source with the stable compiler, outside the repository. It uses FPC's
own Wasm assembler and linker, so no LLVM tools are needed.

```
mkdir -p ~/fpc-wasm && cd ~/fpc-wasm
git clone --depth 1 https://gitlab.com/freepascal.org/fpc/source.git source
cd source
git apply /path/to/opensloper/web/engine/fpc-wasi-fexpand.patch
make crossall crossinstall OS_TARGET=wasip1 CPU_TARGET=wasm32 PP=ppcx64 \
  INSTALL_PREFIX=$HOME/fpc-wasm/install FPMAKEOPT="-T 4"
```

The patch takes `FPC_FEXPAND_DRIVES` and `FPC_FEXPAND_UNC` out of
`rtl/wasicommon/sysutils.pp`: WASI has no drives, and with them
`ExpandFileName('/data/x')` gives `//data/x`, so no file opens by its full
path. FPC's own `dos` unit for WASI already leaves them out. After changing
the RTL, build from clean (`make distclean`) rather than over the old build.

`build.sh` looks for the compiler in `~/fpc-wasm/install/lib/fpc/3.3.1`; set
`FPC_WASM` to that folder of another install.

## Building and comparing

```
./opensloper-make.sh build      # the desktop CLI, which compare.py runs too
web/engine/build.sh
python3 web/engine/compare.py   # every case, with the time each took
```

To try requests by hand, mount the folder the files are in:

```
echo '{"jsonrpc":"2.0","id":1,"method":"open","params":{"path":"/data/skirt-pieces.sloper"}}' |
  node --no-warnings web/engine/run.mjs tests/patterns
```

Paths inside the engine are WASI paths under `/data`. Node 20 or later is
needed for `node:wasi`.
