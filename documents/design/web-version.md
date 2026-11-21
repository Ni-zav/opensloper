# Web version

Part of the [OpenSloper design](../opensloper-design-document.md). Planned, not built beyond a spike. A web version runs in the browser with the same Pascal engine as the desktop apps, compiled to WebAssembly, under a new TypeScript editor, with a Django server for accounts, cloud storage, subscriptions and the marketplace.

**Why it is possible.** The core has no LCL dependency and the Automation API already exposes every document operation as JSON-RPC, so the web needs a new UI, not a new engine, and name rules, formula checks and undo are the same code everywhere.

| Part | Runs in | Language | Does |
| --- | --- | --- | --- |
| Engine | Browser (Web Worker) and server | Pascal, compiled to Wasm | Core, document and API layers: evaluation, undo, pieces, exports |
| Editor | Browser | TypeScript | Canvas, tools, panels; talks to the engine through the API |
| Server | Server | Python, Django | Accounts, cloud files, subscriptions, marketplace, server-side checks and exports |

The editor runs in the browser: sending every drag to the server would make dragging lag, so the server never takes part in interactive drafting.

## Engine

- **Compiler:** FPC's `wasm32-wasip1` target, only in the development compiler (trunk 3.3.1), so the web build uses a self-built cross-compiler while the desktop stays on the stable one; the core must compile with both, which `opensloper-make.sh test` will check. pas2js was rejected: it has no pointers, which Clipper2 uses.
- **One entry point**, `handle(request) → response`, taking and returning a JSON-RPC message as text, the same as `opensloper-cli serve`. Methods the editor needs are added to the Automation API, so the desktop's MCP server gains them too.
- **In the module:** `src/core`, `src/document`, `src/api` and the PDF, SVG and DXF writers. No LCL and no BGRABitmap, so `render` gives SVG only; PNG must be reached through something the module can leave out.
- **Shared UI logic moves behind the API** rather than being rewritten in TypeScript: `Sloper.UI.Snap`, `Sloper.UI.Scene`, `Sloper.UI.RulerTicks` with `Sloper.UI.View`, `Sloper.UI.Completion` and `Sloper.UI.ObjectList`.
- **Runs in a Web Worker**, so a slow evaluation never freezes the page.

**Spike results** (branch `web-spike`, `web/engine/`). FPC trunk compiles the core, document, API, output and Clipper2 unchanged, with its own Wasm linker. Every regression case gives the same objects, values, states and SVG as the desktop, and layout exports are byte for byte the same. A formula edit with the bodice block's full evaluation takes 3.7 ms in Wasm against 1.7 ms native; the module is 4.3 MB, 570 KB with Brotli. In headless Chromium the engine is ready in about 45 ms and an edit takes 3 to 18 ms at the median, so evaluating on every drag in a worker is affordable. Two fixes were needed: `Sloper.Core.AppPaths` now treats WASI as neither Windows nor Unix, and FPC trunk's WASI `ExpandFileName` doubles a leading `/` (patched locally, to report to FPC).

## Files and storage

The browser has no ordinary filesystem, so the engine stops opening files by path: storage gains functions that read and write strings, with the path functions as wrappers, and the API gains `open` and `save` variants that carry contents. References between files stay relative paths with `/`, resolved by whoever supplies the file, so a set of files moves between desktop and web unchanged. Files live in the user's cloud library or, without an account, in browser storage, with import and export of ordinary files. File watching becomes the server telling open editors a file changed, under the same rules. File formats do not change.

## Editor

A TypeScript single-page app per job, as on the desktop, sharing one engine module; drafting and measurements first, publish after. The canvas draws from the computed geometry the engine reports (Canvas2D, WebGL if needed), not from `render`'s SVG. Tools, shortcuts, snapping, undo steps and colours match the desktop, following these design files. Output is written by the engine and downloaded; printing goes through the browser's PDF viewer.

## Server

Django serves the editor and `.wasm` file, accounts (with the admin as back office), the cloud library (folders, version history, sharing; files stored as they are), subscriptions, the marketplace (uploads checked by the engine) and simple pages as templates. It runs the same engine for jobs that need no browser (checks, previews, PDFs), in a task queue, preferably as `opensloper-cli serve` subprocesses, else the Wasm module through `wasmtime`, and only if both are too slow the core as a shared library. It can offer the Automation API as an MCP endpoint over a user's cloud files. Its own packages are kept to what the job needs and locked, and nothing they use reaches the engine.

**Licence.** The engine and editor sent to the browser are distributed, so GPLv3 applies and the source is offered. The Django server is not distributed, so GPLv3 does not require publishing it (the project does not use AGPL); server code linked with the engine is treated as GPL. To be checked with a lawyer before the service is sold.

## Open questions

- Should the shared UI units move into `src/core`, or be compiled into the module where they are?
- Plain TypeScript or a UI library for the panels?
- Does the web version start with drafting, or with measurements as Django forms?
- Can the desktop apps open and save cloud files with the same accounts, and when?
- Should the web editor work offline, as an installable web app?
