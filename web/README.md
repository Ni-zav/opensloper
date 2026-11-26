# The web version

The web design app (issue #78), and the Publish app being built (issue
#85), as `documents/design/web-version.md` plans them: the engine (`engine/`, the Pascal core compiled to WebAssembly) in a Web
Worker, under an editor in plain TypeScript. Files stay on the user's
machine: the page opens and saves them as text, and sends nothing anywhere.

| Folder          | What it is                                                                                                                                                                                                  |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `engine/`       | The engine's Wasm build and the spike's timing page (`engine/README.md`)                                                                                                                                    |
| `src/engine/`   | The worker that runs the engine, and `Engine`, which calls it                                                                                                                                               |
| `src/document/` | `PatternDocument`, the open pattern as the desktop's `TPatternDocument` is to its panels, and `LayoutDocument`, the open layout                                                                             |
| `src/editor/`   | Copies of Pascal logic run on every frame (`view.ts`, `labelPlacement.ts`), and the engine's scene and tables, typed                                                                                        |
| `src/ui/`       | The canvas, its painter and tools, side tabs, list panels and the properties panel, shortcuts and strings, named after their `src/ui` units                                                                 |
| `src/design/`   | The design app's page and `main.ts`, as `Sloper.Design.MainForm`                                                                                                                                            |
| `src/publish/`  | The Publish app's page and `main.ts`, as `Sloper.Publish.MainForm`                                                                                                                                          |
| `tests/`        | Unit tests (`*.test.ts`, `node --test`); `design.ts`, `files.ts`, `offline.ts`, `publish.ts`, `publishFiles.ts` and `publishOffline.ts` drive the built apps in headless Chromium, `browser.ts` serves them |
| `bundle.ts`     | Bundles the pages with esbuild into `out/design`, `out/publish` and `engine/out/browser`                                                                                                                    |

So far the canvas draws the scene (pieces with their marks, notches and
direction, edges, selected seams, notes and callouts, markers, points and
labels placed clear of each other, and the selected curves' handles), zooms
with the wheel, pans with the middle button, selects by clicking and boxing,
and drags points, notes, curve handles and callout tips as one undo step;
every drawing tool of the desktop's works (Point, Line, Curve, Circle,
Rectangle, Piece, Notch, Seam, Text and Callout), and a note's text is typed
over the canvas. Open, Measurements, Save, Save as (where the browser has
File System Access, which saves files in place and finds a pattern's
measurement file in a folder granted once; elsewhere files are uploaded and
downloaded), Undo, Redo, Fit, the user guide's
example patterns (copied from `docs/examples` when the app is built), the
role box and the labels mode are on the toolbar. The side panel has the
Objects, Variables and Measurements tabs, searchable, with the Objects tab
following the canvas selection and setting it, the Variables tab edited in
the grid, with name completion in formulas, and the Measurements tab edited
in the grid too, its edits in bold until Save writes the measurement file,
with the size box and the test size. The Properties tab, first as on the
desktop, shows the selected object's rows as the engine lists them: name and
formulas edited with completion, refused entries kept in red with the reason,
and choices, boxes, numbers, colours and buttons, with a piece's cut, fold,
darts, own allowances, ends, grainline, material and fill, and a note's text,
size, look and font, with formula suggestions under a formula's row.
Work not yet saved is kept in the browser (OPFS) and offered back after
the tab that had it closes.
A service worker keeps the app for offline use and installation, with an
Update button when a new build is ready.

The Publish app (`out/publish`) opens a layout with its patterns and
measurement files, or patterns to start one, and previews its pages, pieces
and notes. Pieces and notes are dragged, turned and placed from the tray, and
pages left out. Its side panel has the desktop's tabs but Claude's: Patterns,
Pieces, Materials, Information Block, Notes, Output and Problems. It prints
through the browser and exports PDF, SVG and DXF-AAMA; Machine DXF stays a
desktop export. The keys are the desktop's. With File System Access it saves
in place and finds a layout's files in a granted folder. Work not yet saved
is kept and offered back, and a service worker of its own keeps it for
offline use.

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
(cd web && npm run test:browser) # the app in a headless browser (SCREENSHOT=name keeps name.png)
python3 -m http.server 8766 --bind 127.0.0.1 --directory web/out/design  # from the repository's root
```

The browser tests use `/usr/bin/chromium` on Linux and Google Chrome in
`/Applications` on macOS. Set `CHROMIUM` to use a different browser executable.

The app is then at `http://127.0.0.1:8766/`; a module worker does not load
from `file://`. Its service worker answers from the build it
kept, so after rebuilding, use the Update button (or the browser's developer
tools) to load the new one. Open a `.sloper` file, choosing its measurement file with it,
or later with Measurements….

`npm run check` runs `tsc`, Oxlint and Prettier, as the TypeScript section of
`documents/coding-standards.md` describes, and `npm run format` lays the
files out; `./opensloper-make.sh check` and `format` run them as well.
