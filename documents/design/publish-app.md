# Publish app

Part of the [OpenSloper design](../opensloper-design-document.md). `opensloper-publish` brings finished pieces from one or more patterns together and prints them, as KiCad splits schematic and PCB editing. The user pages (Publish) describe it as used.

**Why a separate app.** The pattern defines the pieces and publishing only arranges and prints them, so nothing is synchronised back. The design app needs no paper, printer or nesting code, and the publish app no snapping or formula editing. Both link the same core and evaluate patterns themselves.

| Design app (pattern file) | Publish app (layout file) |
| --- | --- |
| Geometry, formulas, variables | Which patterns and measurement sets to use |
| Pieces: outline, allowance, grainline, notches, labels, cut count | Placement of each copy: position, quarter turns, flip |
| Pattern notes and callouts | Information block and sheet notes |
|  | Paper, margins, overlap, marks, output kind, profiles |

Printer calibration is neither: it is a preference.

**Layouts.** A layout lists its sources, each a pattern with a measurement set and size, with IDs from the layout's own never-reused counter; the same pattern may appear twice in two sizes. Placements refer to a piece by source and piece ID and are plain numbers, not formulas: a layout arranges finished pieces. A placement gives the top left of the cutting line after any flip and turn, so it stays put when the piece grows. One file holds one arrangement; A4 tiles and one A0 sheet are two layouts. The sources, their counter, loading and change checks are shared with the drape app in `Sloper.Core.PatternSources`.

**Keeping in step.** The publish app reads saved files, never the design app's unsaved edits. Once a second it compares a checksum of each source's files (file times only go to the second), and a changed file must read the same on two checks before it is loaded. New pieces wait in the tray; a deleted piece is a problem, never dropped silently. Publish… in the design app opens the pattern's layout (same name, `.slayout`) or starts one.

## Finding an open window

Each publish window listens on the apps' link (`Sloper.API.AppLink`), and Publish… asks every window listening, newest first, to `show` the pattern's layout by its full path. The one showing that file comes to the front; when none does, a new publish app starts. A window showing another layout is never reused, since that would replace the user's work: one window per layout. Drape… in the design app works the same with drape windows.

- **The link is the automation socket's plumbing** under another kind of endpoint (`publish-<pid>`, `measurements-<pid>`, `design-<pid>`, `drape-<pid>`): the same private run folder, token and listener thread. Messages are JSON-RPC: `show`, answered `{"done": true}` or `false`, and the `preferences` notification every app listens for.
- A file left by a crash is removed when nothing answers; each window has 3 s to answer.
- **Coming to the front** is the platform's part: on Windows the design app calls `AllowSetForegroundWindow` first; on X11 most window managers raise the window; on Wayland it can only be marked, since that needs an `xdg-activation` token Qt 5 cannot use.
- **Rejected:** scanning windows by title (different per platform, impossible on Wayland), keeping the started process (says nothing of the layout shown), and `SimpleIPC` or UniqueInstance (one server per app, while there may be several windows). It is not the long-running service rejected under the measurements app: it is a listener inside each window that ends with it.

## Placing and problems

**Rotation in 90° steps**, so the grainline stays square to the sheet. On paper the printed grainline shows how to cut, so a turn does not matter; where the piece is cut as it lies, a quarter turn is a warning. A piece cut twice gets two placements, the second flipped when `cut.mirrored` is set.

**Problems.** A missing file, a deleted or failing piece, and a layout with nothing placed block export, so a blank PDF is never written. Unplaced copies, overlaps, pieces off the sheet, notes over pieces and odd rotations are warnings. The status bar counts them and how many stop printing; the Problems tab lists them, blocking ones in red. Each `TLayoutProblem` names its placement or sheet note, so choosing it selects it.

**Output kinds** (`kind` in `output`):

- **Tiled.** Pages with row and column captions (A1, B2), overlaps with marks that make a whole shape across two sheets, empty pages left out, and a cover with the test square, the print-at-100% reminder and the page map. Right-clicking a page leaves it out (`excludedPages`), cleared when paper or overlap change. A4, A3, Letter or custom. More than 10,000 pages (`MAX_TILE_PAGES`) is a problem, so a stray number never asks for billions.
- **Large format.** One sheet `rollWidth` wide (914 mm), as long as needed.
- **Projector.** One dark sheet with thick light lines and large labels, for projecting onto fabric.
- **Material sheet.** A fabric width or board, one material at a time (see Cutting machines).

Calibration scales everything printed at true size, including the test square. A fold piece prints as the half with its bracket, except where it is cut as it lies. `fill` tints or hatches pieces for that print.

**Information block and sheet notes.** The information block (`title`: `corner`, `fields`, `everyPage`) prints on the cover or beside the test square, optionally on every tile: plain lines chosen from a list, with nothing to type or place (`Sloper.Output.TitleBlock` places it for the PDF and preview alike). Sheet notes are text in layout space, dragged like pieces, with fields filled when printed; a note makes its page print. Pattern notes print with their pieces and cannot be moved here.

**Code.** `src/publish` holds the window; loading, tiling, previews and exports are in `src/output` (`Sloper.Output.Layout`, `.Tiling`, `.LayoutPDF`, `.Preview`, `.TitleBlock`), so `opensloper-cli export LAYOUT` writes the same files without a window. `TLayoutDocument` keeps undo as the layout's text before each change.

## Printing

The publish app prints at true scale with notes alongside, so no third-party tiling software is needed, a gap found in practice with Seamly2D. The window is one interactive screen, not a dialog of settings: a live preview of pieces on the page grid, pieces dragged and turned with the page count following, pages clicked out of the print, and everything saved in the layout so reprinting after a measurement change is one click.

**Scale accuracy.** A test square on the first page (10 cm, or 4 in on Letter), a "print at 100%" reminder, and calibration factors in Preferences.

**Print… prints the PDF**, the same file as Export PDF, with scaling off, so what prints is what exports. On Linux and macOS it goes to CUPS (`lpstat` for printers; `lp` with `print-scaling=none`, `fit-to-page=false`, the paper as media and `page-ranges`, so the cover can be printed alone to measure the square). On Windows it goes to the default PDF viewer's print command, with no scaling guarantee, and the dialog says to choose 100%. A projector layout is not printed. Code: `Sloper.Output.Printing` and `Sloper.Publish.PrintDialog`.

Drawing to a printer canvas (LCL `Printers`) was rejected: a second renderer beside the PDF writer, whose scale depends on each driver. If printing the PDF gives trouble, the fallback is an abstract drawing surface that both the PDF writer and a printer canvas implement.

**The PDF writer** (`TPDFWriter`) is our own: exact scale, uncompressed, and the same layout gives the same bytes, which tests compare. Default-font text is the built-in Helvetica; named fonts are embedded (see [Annotations](design-app.md#annotations)).

## Output profiles

The design app stores every marking; the publish app decides which reach the output (`Sloper.Core.OutputProfiles`). A profile describes a kind of print, not a pattern, so profiles live in `settings.json` and a layout stores only the name (`outputProfile`). A profile lists the `roles` and `pieceMarks` to include, `allowance` (`keep`, or `none` to cut on the seam line) and optional paper `styles` per role. The cutting line always prints. A name not in the settings blocks export, since a print missing its stitch lines would be sewn wrongly. `none` changes the outline itself, so the preview, checks, packing and every export use the seam line.

| Profile | Roles | Piece marks | Allowance |
| --- | --- | --- | --- |
| Home printing | All | All | Keep |
| Plotter or laser cutter | Cut | Holes, stitch holes | Keep |
| Leather | Stitch, cut, skive, edge finish | Notches, grainline, labels, holes, stitch holes | None |
| Instructions sheet | Placement, stitch, fold | Seam line, notches, labels | Keep |

The four built-in profiles cannot be changed, so a layout naming one always prints the same; their names stay English, since layouts store them.

**Notes on paper.** A note prints with a piece when anchored to it or one of its points or edges, or when its top left lies inside the cutting line; it follows the piece's placement, upright when the piece is flipped. A print note in no piece is a warning. DXF carries no notes.

## Draft export

File → Export Draft SVG… and `opensloper-cli export-draft` write the draft itself as a true-scale SVG in mm, for teaching, documentation and review in Inkscape. It needs only a draft, even an unfinished one, and is not for cutting. In the app it matches the screen; the CLI names everything only with `--labels`, and `--upto` draws the pattern as it was when an object was added, for tutorial pictures.

## Other exports and packing

The problems that block a PDF block these too.

**SVG** (`Sloper.Output.LayoutSVG`): one true-scale file at the layout's positions, one group per copy with cut, seam, marks and label groups, so a cutter can leave out the seam line. Paper things (pages, marks, calibration, notes) are left out.

**DXF-AAMA** (`Sloper.Output.LayoutDXF`): ASCII R12 from our own writer, one block per piece in its own coordinates with y up and its cut count as quantity; placed pieces only; sizes as separate blocks. Curves are polylines, a fold piece the half with a mirror line.

| Layer | Content |
| --- | --- |
| 1 | Cut line and piece text: name, size, quantity, material |
| 14 | Seam line |
| 4 | Notches |
| 7 | Grainline |
| 6 | Fold (mirror line) |
| 8 | Marking lines and point markers |
| 13 | Holes and stitch holes, as points |

ASTM D6673 is paywalled and withdrawn, so the layers follow Valentina's GPL exporter, with 8 and 13 from CAD systems' published lists. It reads cleanly in `ezdxf` but has not been tried on a real cutting system.

**Pack Pieces** (and `opensloper-cli pack`, `Sloper.Output.Nesting`) nests every copy's cutting line, tray included, as one undo step: longest side first, each as near the top then as far left as it fits, as it stands or a quarter turn (on a material sheet only with `allowTurns`), at least 10 mm apart; the same input gives the same result. Where a piece cannot go is the union of no-fit polygons (the Minkowski sum of each placed outline and the new one turned a half turn, grown by half the gap), worked out once per pair of shapes; the nester unions each edge's parallelograms, then the rows pairwise, which is about a hundred times faster than Clipper's `MinkowskiDiff` on curved pieces. Tiled output tries each column count for the fewest pages; sheets pack to the width for the shortest length. Pieces that cannot fit go below and are counted. An existing arrangement that is already better is kept.

## Cutting machines and material sheets

Laser cutters, plotters and cutters such as Cricut treat line types differently, so exports keep them apart:

| Line type | What | Usual SVG colour |
| --- | --- | --- |
| Cut | Cutting line and cut-role lines | Red |
| Score | Fold-role lines | Blue |
| Mark | Placement and stitch lines, seam line, notches, grainline, fold bracket, buttons, match dots | Black |
| Engrave | Labels and text | Green |
| Hole | Holes and stitch holes, as true circles | Red |

- **Machine profiles** give each line type a colour, layer, width and on/off switch. They describe a machine, so they live in the settings, with a built-in `Standard`; a layout stores the name, and one not in the settings blocks export, since the wrong colours would cut the wrong lines.
- **Cut order:** score, mark, engrave, holes, then cut, since software that follows file order would otherwise free a piece before its holes are cut.
- **Machine DXF** writes pieces as placed, y up, on the profile's layers, sharing a writer with DXF-AAMA. Labels are text, so they depend on the machine's fonts.

**Cut as it lies.** On a material sheet, a projector or with a machine profile, nobody reads the printed grainline, so a quarter turn is a warning, and a fold piece is opened out to the whole piece; a hole on the fold line makes the piece invalid. The preview, checks, packing and exports all use the whole piece; DXF-AAMA still writes the half.

**Material sheets** (`kind` `material`): `materialWidth` by `materialLength` (0 for a roll), as one sheet. `material` limits a layout to one material by name (material IDs belong to each pattern), so each material gets its own cutting layout. Choosing a material takes its size from the first pattern that gives one, copied once, not linked (`TLayout.TakeMaterialSize`).

## Material needed

How much of each material the layout's patterns take, for buying fabric: the Materials tab, the `{materialneeded}` field and `opensloper-cli materials LAYOUT|PATTERN [--json]` (`Sloper.Output.MaterialNeeded`).

- **The whole design, not the sheet.** Every valid piece of every source counts, placed or not, so the estimate makes its own cutting plan, each piece with its grainline along the material.
- **A roll is cut folded** lengthwise, as home sewers cut: half the width over two layers. Fold pieces go down the fold; a mirrored pair takes one place on both layers; a piece too wide for the folded roll is cut unfolded after, and one wider than the roll is left out, each with a note.
- **A sheet is cut single layer**, as many sheets as it takes. With no size, the pieces' area and the narrowest roll every piece fits.
- **Packing** is bounding boxes (`PackBoxes`), so the estimate errs generous; true shapes are in Open items.
- **Across patterns** a material is matched by name; its size comes from the first pattern that gives one.
