# OpenSloper design

The design of OpenSloper and the reasons behind it, a file per app and the Automation API. Start with the [overview](../opensloper-design-document.md), which covers what every app shares. The files describe what is built and the decisions behind it; what is not built yet is in [Open items](open-items.md). When a design decision changes, change the file it belongs to in the same commit.

| File | What it covers |
| --- | --- |
| [Overview](../opensloper-design-document.md) | Overview, architecture, files, preferences, platforms and releases, dependencies, testing, documentation, translation, privacy |
| [Measurements app](measurements-app.md) | Measurement files and size tables, the catalogue, other programs' formats |
| [Design app](design-app.md) | Evaluator, names and IDs, formulas, units, operations, the canvas, markings, seams, materials, notes, accessories, features, the Garment tab |
| [Publish app](publish-app.md) | Layouts, printing, output profiles, exports, cutting machines, material needed |
| [Drape app](drape-app.md) | Placing pieces round a body in 3D and draping them in Blender |
| [Automation API and command line](automation-api.md) | The CLI, the JSON-RPC API, MCP, live editing, the Claude tabs, safety, PNG drawing |
| [Web version](web-version.md) | The planned browser version: the engine in WebAssembly, a TypeScript editor, a Django server |
| [Open items](open-items.md) | Roadmap, to do, open questions and future ideas |

The apps follow the files they own, each reading only the ones before it: measurements → design → publish and drape.
