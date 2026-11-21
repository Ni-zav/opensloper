# Measurements app

Part of the [OpenSloper design](../opensloper-design-document.md).

Measurement files are edited in their own application, `opensloper-measurements`, as SeamlyMe does for Seamly2D. One measurement file drives many patterns, and recording someone's measurements is a different job from drafting, sometimes by a different person: it needs a form, not a canvas. It is also where Valentina and Seamly2D files are imported and size tables kept. The user pages (Measure) describe it as used.

**One format, one or several sizes.** A file is one person's set, with a `value` per measurement, or a size table, with `sizes` and a `values` list per measurement (`null` for a size with no value). Patterns read `@waist` either way, and everything reads the value of the selected size, the first until another is chosen. Wherever a file is chosen a size is chosen with it; a size with no value for a key the pattern uses is one error ("@waist has no value for size 42"). A table keeps at least one size; the first size added to a personal set takes over its values. Pattern-specific ease stays in the pattern's `#` variables.

**One unit is the central control.** All reading, writing and editing of measurement files goes through `Sloper.Core.Measurements`, used by every app and the CLI, so key rules, units and formatting are the same everywhere. A long-running service the apps connect to was rejected: process management and crash handling for a problem a careful write and a merge by key already solve.

**No measurement set needed to draft.** A pattern can use plain numbers and `#` variables; only formulas with an `@` key show the missing-key error, and adding a key from that error first offers to make a measurement file.

**Small edits from the design app.** Its Measurements tab adds a missing key and changes a value or description. Edits are held, shown bold with `*`, until Save writes them in one write. Everything else (sizes, order, imports) is done in the measurements app, which File → Measurements → Edit in Measurements App… opens at the file. These edits are not part of the pattern's undo, since the file belongs to every pattern that uses it.

**Writing safely.**

- Every save of small edits re-reads the file just before writing, applies its changes and writes atomically, so a change made elsewhere is never overwritten; `ChangeMeasurementsInFile` makes every change or none.
- Every app with a measurement file open watches it. A changed file must read the same on two checks before it is taken in, and one that does not parse is left alone. With no unsaved edits the app reloads; the measurements app with unsaved edits merges by key against the file as last read, asking only when a key changed on both sides. Saving over a file that changed since it was read is refused until the change has been taken in.
- `TMeasurementDocument` keeps its own undo history of the file's text (`TTextHistory`, shared with the publish app); a change read from disk clears it.

**From the CLI and the Automation API:** `measurements set`, `list` and `missing`, and `get_measurements`, `set_measurement` and `missing_measurements`, so a script or Claude can add a missing measurement. `missing` exits with 1 when something is missing, as `check` does.

## Measurement catalogue

`data/measurement-catalogue.json`, read by `Sloper.Core.Catalogue`; without it the table still works. It lists the measurements most drafting needs (72, from Seamly2D's 246); more are added as entries, with no code change. It also holds the figure outlines.

- Keys are whole words with no abbreviations: `waist_circumference`, not `waist_circ`. Custom keys remain allowed, and keys already in use are never renamed.
- Definitions follow ISO 8559-1:2017 in meaning; the descriptions are our own wording.
- Each entry has `key`, `name`, `group`, `description`, `howTo`, `view` (front, back or side), `overlay` (its line on the figure) and a typical `range` in mm. A value outside the range is a warning, never a refusal.
- `translations` gives the entry's names in other programs' files by format (`{ "seamly2d": ["waist_circ"] }`), the first being the one exported, so the catalogue is also the import and export table. `knownNames` lists a format's names with no entry yet, so they go back out unchanged.

## Other programs' formats

`Sloper.Core.SeamlyFormat` reads and writes Seamly2D's `.smis` and `.smms` and Valentina's `.vit` and `.vst` (the same files with the root renamed). Versions older than individual 0.3.0 and multi-size 0.4.0 are refused, and exports are checked against their schemas.

- **Nothing is altered silently.** A name is translated to our key, kept as a custom key (dropping Seamly2D's leading `@`), or corrected or numbered when it breaks our rules or is taken; the app lists what was renamed, kept and changed.
- Values written as formulas are worked out and stored, with a note; anything else (a function, a value past a double's range, a formula nested past `MAX_FORMULA_DEPTH`) is left at 0 and listed. The import runs with floating point exceptions masked, so NaN or infinity never reaches a file.
- A multi-size file gives a base value with an increase per 2 cm of size and 6 cm of height, while a size table has one dimension: importing makes a column for each size within three steps of the base, at the base height, and reports the heights left out. Exporting needs even sizes from 22 to 72, takes the middle as the base, fits a straight line through the first and last values and reports any value more than 0.5 mm off it.

## Body figure

Front, back and side outlines drawn by us (no third-party images, so no licence questions). The file's measurements are drawn faintly and the current one highlighted; clicking a line selects its row. Each measurement's line comes from its catalogue `overlay`, so a new measurement is a catalogue entry, not a new picture.

## Editing

Measurements are added from the catalogue by group, with search, leaving out those already in the file; an added one takes the catalogue's description and starts at 0 (which the range warning points out) or, in a size table, empty. Values are entered in the display unit and stored in mm. Given a pattern, the app lists what the pattern uses that the file cannot give (missing keys, sizes with no value), with a button to add or go to each.
