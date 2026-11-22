# The web version

The web design app (issue #78), as `documents/design/web-version.md` plans
it: the engine (`engine/`, the Pascal core compiled to WebAssembly) in a Web
Worker, under an editor in plain TypeScript. Files stay on the user's
machine: the page opens and saves them as text, and sends nothing anywhere.

| Folder          | What it is                                                                                               |
| --------------- | -------------------------------------------------------------------------------------------------------- |
| `engine/`       | The engine's Wasm build and the spike's timing page (`engine/README.md`)                                 |
| `src/engine/`   | The worker that runs the engine, and `Engine`, which calls it                                            |
| `src/document/` | `PatternDocument`, the open pattern as the desktop's `TPatternDocument` is to its panels                 |
| `src/editor/`   | Copies of `src/editor` logic run on every frame (`view.ts`), and the engine's scene and tables, typed    |
| `src/ui/`       | The canvas, its painter and tools, shortcuts and strings, named after their `src/ui` units               |
| `src/design/`   | The design app's page and `main.ts`, as `Sloper.Design.MainForm`                                         |
| `tests/`        | Unit tests (`*.test.ts`, `node --test`) and `design.ts`, which drives the built app in headless Chromium |
| `bundle.ts`     | Bundles the pages with esbuild into `out/design` and `engine/out/browser`                                |

So far the canvas draws the scene, zooms with the wheel, pans with the middle
button, selects by clicking and boxing, drags points as one undo step, and
the Point tool adds points where they snap; Open, Measurements, Save, Undo,
Redo and Fit are on the toolbar. The other tools and the panels follow the
same pattern.

## Setting up

Node and npm come from the repository's Python `venv`, through `nodeenv`, so
nothing is installed system-wide:

```
./venv/bin/pip install nodeenv
source venv/bin/activate && nodeenv -p --prebuilt --node=lts
cd web && npm ci
```

## Building and running

```
./opensloper-make.sh web       # the engine, then npm run build: check, unit tests, bundle
cd web && npm run test:browser # the app in headless Chromium (CHROMIUM names the browser)
python3 -m http.server 8766 --bind 127.0.0.1 --directory web/out/design
```

The app is then at `http://127.0.0.1:8766/`; a module worker does not load
from `file://`. Open a `.sloper` file, choosing its measurement file with it,
or later with Measurements….

`npm run check` runs `tsc`, Oxlint and Prettier, as the TypeScript section of
`documents/coding-standards.md` describes, and `npm run format` lays the
files out; `./opensloper-make.sh check` and `format` run them as well.
