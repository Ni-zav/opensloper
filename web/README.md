# The web version

The web design app (issue #78), as `documents/design/web-version.md` plans
it: the engine (`engine/`, the Pascal core compiled to WebAssembly) in a Web
Worker, under an editor in plain TypeScript. Files stay on the user's
machine: the page opens and saves them as text, and sends nothing anywhere.

| Folder          | What it is                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------------- |
| `engine/`       | The engine's Wasm build and the spike's timing page (`engine/README.md`)                                              |
| `src/engine/`   | The worker that runs the engine, and `Engine`, which calls it                                                         |
| `src/document/` | `PatternDocument`, the open pattern as the desktop's `TPatternDocument` is to its panels                              |
| `src/editor/`   | Copies of Pascal logic run on every frame (`view.ts`, `labelPlacement.ts`), and the engine's scene and tables, typed  |
| `src/ui/`       | The canvas, its painter and tools, side tabs and list panels, shortcuts and strings, named after their `src/ui` units |
| `src/design/`   | The design app's page and `main.ts`, as `Sloper.Design.MainForm`                                                      |
| `tests/`        | Unit tests (`*.test.ts`, `node --test`) and `design.ts`, which drives the built app in headless Chromium              |
| `bundle.ts`     | Bundles the pages with esbuild into `out/design` and `engine/out/browser`                                             |

So far the canvas draws the scene (pieces with their marks, notches and
direction, edges, selected seams, notes and callouts, markers, points and
labels placed clear of each other, and the selected curves' handles), zooms
with the wheel, pans with the middle button, selects by clicking and boxing,
and drags points, notes, curve handles and callout tips as one undo step;
every drawing tool of the desktop's works (Point, Line, Curve, Circle,
Rectangle, Piece, Notch, Seam, Text and Callout), and a note's text is typed
over the canvas. Open, Measurements, Save, Undo, Redo, Fit, the user guide's
example patterns (copied from `docs/examples` when the app is built), the
role box and the labels mode are on the toolbar. The side panel has the
Objects, Variables and Measurements tabs, searchable, with the Objects tab
following the canvas selection and setting it and the Variables tab edited
in the grid, with name completion in formulas; editing measurements and the
Properties tab follow the same pattern.

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
cd web && npm run test:browser # the app in headless Chromium (CHROMIUM names the browser; SCREENSHOT=name keeps name.png)
python3 -m http.server 8766 --bind 127.0.0.1 --directory web/out/design
```

The app is then at `http://127.0.0.1:8766/`; a module worker does not load
from `file://`. Open a `.sloper` file, choosing its measurement file with it,
or later with Measurements….

`npm run check` runs `tsc`, Oxlint and Prettier, as the TypeScript section of
`documents/coding-standards.md` describes, and `npm run format` lays the
files out; `./opensloper-make.sh check` and `format` run them as well.
