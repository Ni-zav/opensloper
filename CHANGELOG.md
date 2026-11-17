# Changelog

What changed in each version of OpenSloper. Changes are added under the
version being worked on, the `APP_VERSION` in
`src/core/sloper.core.version.pas`, and the release workflow puts that
version's section in the notes of its GitHub release. A version left without
notes here gets the list of its commits since the last release instead
(`opensloper-make.sh release`). Issue numbers (#3) link to GitHub.

The layout follows [Keep a Changelog](https://keepachangelog.com): Added,
Changed, Fixed and Removed under each version.


## 0.4.0

### Added

- Formula suggestions (#26): a wand beside a field holding a plain number
  lists formulas that give about the same value, such as `@waist/4` for an
  offset of 175 mm, built from measurements, variables and other edges'
  lengths and angles, closest and simplest first. Hovering one shows where
  it would put the point; choosing one writes it into the field. While the
  list is open, dragging the point or nudging it with the arrow keys changes
  only that field, along a guide line, and the list follows the value.
- With a size table, each suggestion also shows its values at the smallest
  and largest sizes and, in its tooltip, at every size, and hovering it
  outlines the pieces at those two sizes, so a formula that matches only by
  chance stands out (#26).

### Changed

- The user guide has moved to <https://docs.opensloper.com>; Help → User
  Guide, the Python client and the file schemas link there (#43).


## 0.3.0

### Added

- Installers: a `.deb` for Debian and Ubuntu, a `.dmg` for macOS and a
  `setup.exe` for Windows, each registering the pattern, measurement and
  layout files with their apps (#17). The `.tar.gz` and Windows `.zip` stay
  for running from a folder; the macOS `.zip` is replaced by the `.dmg`.
- Every download has the user guide to read offline, and Help → User Guide in
  each app opens it, or the website when the guide is not there (#17).
- A change of preferences reaches the apps already open, without a restart
  (#29).
- A portable install: with a `portable.ini` beside the programs (beside
  `OpenSloper.app` on macOS), settings, recent files and cache are kept in a
  `user` folder beside them and documents in `documents`, and recent files
  there are still found when the drive gets another letter (#30).

- The Claude assistant works on Windows and macOS: their downloads bring
  OpenSSL 3 and Mozilla's root certificates (#31). On Linux it finds the
  system's OpenSSL 3 without the development files, and the `.deb` depends on
  it.
- `opensloper-cli check-connection` says whether the assistant can reach the
  API: that OpenSSL loads, the server's certificate is trusted and it answers
  (#31). The release jobs run it from each download.

### Changed

- The Automation API's `export` refuses to replace a file already there, and
  `set_measurement` asks before it writes the measurement file.
- The Claude assistant checks the server's certificate before sending the API
  key.
- The assistant's conversation ends when another pattern is opened.
- The assistant keeps only its last three draft images in the conversation.
- A tiled print is capped at 10,000 pages; past that the layout has a problem.
- A draft PNG is capped in height, and an empty area is refused.
- Pieces that packing cannot fit are set below the packed ones.
- `opensloper-cli materials` warns about each pattern it could not read and
  exits 2.
- `opensloper-cli layout` refuses a pattern file that is not there.
- Patterns, layouts, measurements and settings are written atomically.
- The measurement and layout undo keep the latest 500 steps.
- File → Save As starts in the pattern's own folder.
- Files ending `.SLOPER` or `.SLAYOUT` are known whatever their case.
- The evaluation graph is built in linear time, and formula references are
  looked up rather than compared with every object.
- An edge is measured once for a repeat, and once when finding coincident
  edges.
- A layout's pieces are placed once when listing its problems, and a garment
  piece is fingerprinted without flattening its edges again.
- The list panels rebuild once a drag ends, and the publish Materials tab
  only when the patterns change.
- Unit conversion tries a number's plain fit once.
- Messages name an input of the wrong kind rather than give its ID.
- The test square's printed size is translatable.
- The design window's actions and toolbars are built with the code the other
  apps share.
- The MCP server and the assistant share their tool result code.
- One array type and one vector normalising function serve all the geometry.
- The design form's `ui_state` answer is named `UIStateJSON`, so it no longer
  hides the form's own `WindowState`.

- The design app's Claude commands are in a new Assistance menu: Ask Claude,
  Anthropic API Key…, Allow Assistants to Connect and Disconnect Assistant.
  Any MCP client can connect, so the window, its consent prompt and its undo
  steps say "assistant" for them; the Claude tab keeps Claude's name, and its
  question box and buttons are off until an API key is set (#37).

### Fixed

- An API edit left open by a method that fails is cancelled.
- A malformed API request without an id gets no reply.
- An API call's repeat point gets its ID inside the call's change.
- An API input given by an ID that does not exist is refused.
- `set_material` names the parameter in its number errors, and `add_point`
  lists every point type.
- An assistant question stopped before any answer is taken back.
- An assistant stream cut off before its end is treated as failed.
- A key changed in Preferences is used on the assistant's next question.
- Stop ends the assistant's request at once.
- The assistant says why its key file could not be saved or removed.
- A reset connection to the Claude API no longer ends the design app.
- JSON nested too deep to parse safely is refused.
- Numbers past a double's range are refused in files, formulas and imported
  measurements.
- IDs from files are kept within 32 bits.
- A transform's sources are read as IDs, not any number.
- A fragment's odd selection or needs is refused instead of raising.
- How deep an imported Seamly formula is worked out is limited.
- A pasted ID from another pattern that the copy does not hold is refused.
- A node is made invalid when a number too large raises as it computes.
- A repeat's count is checked before it is rounded.
- A curve is offset all along when a handle has zero length.
- Two close crossings of large circles are told from a touch.
- Every perpendicular foot on a curve is found, not only the nearest point.
- A curve's crossings are found however close, and where it only touches.
- A repeat is collected once when a piece uses several of its points.
- A point keeps its marker when its operation is changed.
- A point given twice is arranged once.
- A marking a piece's formula also reads cannot be deleted.
- A transform whose copy a piece only marks can be deleted.
- A round corner given the same edge twice is refused.
- A mirror's second axis point is checked when it is made.
- A mirror's axis line cannot be turned into a curve.
- A projector sheet draws in white again after a profile-coloured line.
- The sheet and its pages are sized for the notes printed with pieces.
- Each material and measurement set is listed once, matched whole.
- Nothing is placed for a tray item whose piece has gone.
- New pieces wrap at the roll or material width.
- A fold piece keeps its half when opening it out encloses nothing.
- A repeat is deleted when one of its points is selected.
- Align says why it did nothing when a locked point would move.
- Hidden and dimmed pieces are left out of click choices.
- A pending pick and tool state are dropped when another pattern opens.
- The Garment tab keeps its material and view through undo.
- The formula caret is right with letters beyond ASCII.
- A piece's colour choice starts on its own material's colour.
- `--upto` draws up to a repeat when it names one of its points.
- A layout's `-m` path is stored relative to the layout.
- A pending measurement conflict is dropped when another file is opened.
- Only text names are read from the catalogue's name lists.
- The measurement text that was loaded is remembered, not read a second time.
- The Lines panel no longer outlives the document when the design
  window closes.
- A publish drag no longer loses the piece it moves.
- A header or cell edit is finished before switching measurement files.
- The title fields keep their order when one is ticked or cleared.
- A plain bracket before a link no longer garbles the Python client's
  docstrings.

### Removed

- The hidden Align tab of the design app. Points are lined up and spaced out
  by their formulas and by Tools → Points → Repeat Points; the Automation
  API's `arrange` stays (#36).

## 0.2.0

### Added

- The Garment tab in the side panel shows the pieces as sewn (#4): darts made
  seams are closed, pieces cut on the fold are opened, and each piece is shaded
  as if round a body, arranged as on the canvas. Hovering a piece shows it on
  the canvas and a click selects it there; a selected seam is marked on both
  its sides. It exports SVG and PNG, the Automation API's `render` draws it
  with `garment`, and Preferences set its light.
- Objects can be locked (#16) with Edit → Lock and Unlock, or Locked in the
  Properties tab. A locked object is drawn greyed and cannot be moved, edited
  or deleted, but it can still be selected and used, and its formulas still
  run. The lock is saved with the pattern and is one undo step; the
  Automation API has `set_locked`.
- Overlapping pieces can be hidden, isolated and stacked (#10), from the View
  menu. Hide Piece takes a piece off the canvas with what only it uses; Isolate
  Piece dims everything the piece does not use and puts it out of reach; Bring
  to Front and Send to Back change the drawing order. They are saved with the
  pattern, outside undo, and the Garment tab and Export Draft follow them;
  every piece still prints.
- Notes and sheet notes have a font, bold and italic (#7). The canvas draws
  the font, SVG names it, and PDF embeds it from its TrueType file, cut down to
  the letters used. A font that cannot be embedded prints in the default font,
  with a warning.
- Materials have a size and the material needed is worked out (#19). A
  material can have a width (a roll) or a width and length (a sheet), and can
  allow quarter turns when it has no grain. A piece too big to cut from its
  material is a problem in the design app, `check`, the CLI and the API, each
  piece measured along its grainline. The publish app works out how much of
  each material the layout's patterns take, a roll cut folded in half
  lengthwise and a sheet single layer, and shows it on a new Materials tab, in
  the information block's Material needed line and the `{materialneeded}`
  field; `opensloper-cli materials` prints it. Choosing a material for a
  material sheet takes that material's size. The Automation API's
  `set_material` takes `width`, `length` and `allowTurns`.

### Changed

- The development scripts are one, `opensloper-make.sh`, with the commands
  `test`, `build`, `check`, `format`, `docs`, `package` and `release` in place
  of `run-tests.sh`, `build.sh`, `check-standards.sh`, `format.sh`,
  `build-docs.sh`, `package.sh` and `release-notes.sh` (#22).
- File → Publish… in the design app brings the publish window already showing
  the pattern's layout to the front, rather than opening another each time
  (#18). Only when none shows it is a new one started.
- Menu and toolbar commands are greyed out while they cannot be used (#24),
  in all three apps. A new, empty file has nothing to save, export, print or
  publish; Save waits for a change; and the commands that work on a
  selection, a measurement row or a size column wait for one. Cut, Copy and
  Paste stay on, as they also work in text fields.
- The publish app's Notes tab is two (#14): Information Block, the title
  block renamed, whose Show box turns it on, and Notes. The pages show the
  information block where it prints, with the cover drawn left of the tiles.
  Sheet notes have a frame round them on screen, so they are easy to find,
  and clicking one opens its details on the Notes tab.

### Fixed

- Angles worked out from points (`AngleBetween`, `NormalizeAngle`) were only
  good to about seven figures, as Free Pascal's `FMod` took its
  single-precision form.
- PDF prints text outside Latin-1, such as Greek or Cyrillic, in sheet notes,
  piece labels and notes, in the bundled Noto Sans; it used to print `?`.
- The publish app's Print dialog sizes itself to its contents once shown; with
  a larger font its note was cut off at the bottom.
- The Preferences dialog sizes itself to its contents once shown, within the
  screen, and each tab scrolls when the screen is too small (#12); with a
  larger font the bottom of the Design tab was cut off.
- The publish preview drew sheet notes a quarter larger than they print, and
  their lines further apart.

## 0.1.0

The first release, for trying out: features and file formats may still change.

### Added

- **opensloper-measurements**: one person's measurements or a size table, from
  a catalogue of measurements with body figures.
- **opensloper-design**: points, lines, curves, circles and rectangles placed by
  formulas, in mm, cm or inches; pieces with seam allowances, seams, notches,
  markings, grainlines and materials; transforms, notes and callouts; full undo.
- **opensloper-publish**: pieces laid out on tiled pages, a large sheet, a
  projector or a material width, printed at true size or exported as PDF, SVG
  or DXF.
- **opensloper-cli**: checks and exports patterns and layouts, and serves the
  Automation API, also as an MCP server, so scripts and Claude can draft.
- Ask Claude about the open pattern from the design window's side panel.
- A Zoom tool (Z) in the design window and Zoom Area in the publish window:
  drag a box to zoom to it (#3).
- Zoom In and Zoom Out in the publish window, and Ctrl++ for Zoom In in both;
  Ctrl+= still works (#3).
- Scroll bars on the publish preview (#6).
- Downloads for Linux (x86_64), macOS (Apple silicon) and Windows (x86_64).
