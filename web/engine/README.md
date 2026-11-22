# Web engine (spike)

The OpenSloper engine (`src/core`, `src/document`, `src/api` and `src/output`,
with Clipper2) compiled to WebAssembly for `wasm32-wasip1`, as planned under
`documents/design/web-version.md`, whose Spike results
say what it showed. It is built twice from the same units:

- `engine_serve.lpr`, a WASI program for Node that answers Automation API
  requests, one JSON-RPC message a line on standard input and one reply a line
  on standard output, as `opensloper-cli serve` does;
- `engine_lib.lpr`, a WASI library for the browser that exports
  `engine_handle(request, size)`, taking one request as UTF-8 and giving back
  the reply, with `engine_alloc` and `engine_free` for the memory between.

| File | What it is |
| --- | --- |
| `engine_serve.lpr` | The program: `TApiServer` over stdin and stdout |
| `engine_lib.lpr` | The library: `TApiServer` behind `engine_handle` |
| `browser/` | A page that runs the library in a Web Worker and times it (TypeScript) |
| `stubs/` | Stand-ins for `Sloper.Output.DraftPNG` and `Sloper.Output.GarmentPNG` with the same interface, without BGRABitmap; PNG is refused |
| `build.sh` | Builds `out/engine_serve.wasm` and `out/browser/engine_lib.wasm`; run it through `./opensloper-make.sh web` |
| `run.mjs` | Runs it under Node's WASI, with a folder mounted as `/data` |
| `compare.py` | Runs every regression case through the desktop CLI and the engine, and compares the answers |
| `fpc-wasi-fexpand.patch` | The fix to FPC trunk's WASI `ExpandFileName` the engine needs |

## The compiler

The Wasm target is only in FPC trunk (3.3.1), so the cross-compiler is built
from source with the stable compiler, outside the repository. It uses FPC's
own Wasm assembler and linker, so no LLVM tools are needed.

```
mkdir -p ~/Packages/fpc-wasm && cd ~/Packages/fpc-wasm
git clone --depth 1 https://gitlab.com/freepascal.org/fpc/source.git source
cd source
git apply /path/to/opensloper/web/engine/fpc-wasi-fexpand.patch
make crossall crossinstall OS_TARGET=wasip1 CPU_TARGET=wasm32 PP=ppcx64 \
  INSTALL_PREFIX=$HOME/Packages/fpc-wasm/install FPMAKEOPT="-T 4"
```

The patch takes `FPC_FEXPAND_DRIVES` and `FPC_FEXPAND_UNC` out of
`rtl/wasicommon/sysutils.pp`: WASI has no drives, and with them
`ExpandFileName('/data/x')` gives `//data/x`, so no file opens by its full
path. FPC's own `dos` unit for WASI already leaves them out. After changing
the RTL, build from clean (`make distclean`) rather than over the old build.

`build.sh` looks for the compiler in `~/Packages/fpc-wasm/install/lib/fpc/3.3.1`; set
`FPC_WASM` to that folder of another install.

## Building and comparing

```
./opensloper-make.sh build      # the desktop CLI, which compare.py runs too
./opensloper-make.sh web        # --strip-names takes the function names out of the .wasm files
python3 web/engine/compare.py   # every case, with the time each took
```

To try requests by hand, mount the folder the files are in:

```
echo '{"jsonrpc":"2.0","id":1,"method":"open","params":{"path":"/data/skirt-pieces.sloper"}}' |
  node --no-warnings web/engine/run.mjs tests/patterns
```

Paths inside the engine are WASI paths under `/data`. Node 20 or later is
needed for `node:wasi`.

## In a browser

`browser/` is a TypeScript page: `worker.ts` loads `engine_lib.wasm` in a Web
Worker through the WASI shim `@bjorn3/browser_wasi_shim`, with an in-memory
`/data` folder the page puts files in; `main.ts` fetches a regression pattern
as text, opens, checks and draws it, then times 100 edits. `measure.ts`
opens it in headless Chromium (through `puppeteer-core`, with the system's
Chromium) and prints the times.

Node and npm come from the repository's Python `venv`, through `nodeenv`, so
nothing is installed system-wide:

```
./venv/bin/pip install nodeenv
source venv/bin/activate && nodeenv -p --prebuilt --node=lts
```

Then, with `venv` active:

```
./opensloper-make.sh web                   # also writes out/browser/engine_lib.wasm
cd web/engine/browser && npm ci && npm run build
cd ../../.. && python3 -m http.server 8765 --bind 127.0.0.1 &
cd web/engine/browser && npm run measure -- --pattern bodice-block.sloper --measurements bodice-small.slm
```

`npm run build` first runs `npm run check`: `tsc` in strict mode, Oxlint
with its type-aware rules, and Prettier, as the TypeScript section of
`documents/coding-standards.md` describes; `npm run format` lays the files
out. `./opensloper-make.sh check` and `format` run them as well.

The page is at `http://127.0.0.1:8765/web/engine/out/browser/index.html`
(`?pattern=` and `?measurements=` choose the case). A module worker does not
load from `file://`, hence the server.
