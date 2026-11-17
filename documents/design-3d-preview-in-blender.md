# 3D preview in Blender

Notes for later work on GitHub issue #11 (3D Preview using Blender), written 2026-11-16; placement, the Assembly tab, assembly steps and printed assembly instructions added as its first steps 2026-11-17. The design document's **Blender export (3D preview)** section stays the decision of record; this file is the working plan and estimate behind it. Fold what is decided back into the design document when the work starts.

## Goal

Export what Blender needs to sew a pattern together with its cloth simulation, on a body or on its own, rather than writing a simulator in OpenSloper:

- Triangulated piece meshes (OBJ)
- A JSON file with seam pairs, each piece's placement in 3D and fabric hints
- A body built from the pattern's measurements, when the pattern is worn (OBJ)
- A Blender Python script that imports the pieces, places them, creates sewing springs and runs the simulation in one step

The Garment tab stays the quick, flat look at the finished pieces; Blender is for fit and drape. The exporter lives in `src/output` and reads computed geometry only.

The work starts with **placement** (decided 2026-11-17): the user arranges the flat pieces in 3D in the design app's **Assembly** tab, apart from each other but each facing the way it is sewn, in the right order front to back and inside to outside. That arrangement is an exploded view of the finished item. The user then lists **assembly steps** in the same tab (which seams are sewn in each step, and from which view it is shown), and the publish app prints them as **assembly instructions** in the manner of flat-pack furniture instructions: line drawings, numbered steps, arrows between the edges sewn together, few words. The Blender script, later, starts the simulation from the same arrangement, the sewing springs closing the gaps. Placements and steps are the new definitions in the core model.

The Assembly tab and the instructions come first and stand on their own (decided 2026-11-17); the body and Blender follow.

## What already exists

- **Seams.** `TSeamObject` (`src/core/sloper.core.seam.pas`) lists side A and side B as piece and edge entries, in order along the seam, with direction (`RunsForward`, `Reversed`), ease and lengths. A side may span pieces (a sleeve cap to a front and a back armhole) and have gaps.
- **Darts are seams** whose two sides are adjacent edges of one piece meeting at the apex. Blender can sew them shut like any other seam, so the export keeps darts open rather than closing them as the Garment tab does.
- **Folds.** A piece cut on a fold already gives its whole, opened-out outline (the half and its mirror image).
- **Seam lines.** The Garment builder (`src/core/sloper.core.garment.pas`) works on seam lines, not cutting lines, which is what the mesh is made from. The seam allowance is left out of the mesh.
- **Materials** give a place to hang fabric hints (weight, stretch, stiffness) later.
- **Measurements**: the catalogue (`data/measurement-catalogue.json`) has the heights and circumferences a simple body needs (`height_*`, `neck_circumference`, `bust_circumference`, `waist_circumference`, `hip_circumference`, `upper_arm_circumference`, `thigh_circumference`, `head_circumference`, …).

## New work

| Part | Size | Notes |
|---|---|---|
| **Placement and the Assembly tab**: the definition, file format, commands, guesses, API, and the tab in the design app to set it | Large | See Placement and the Assembly tab below. The first step. Projection and drawing are simple (flat pieces, no OpenGL); handling moves and turns well is the work. |
| **Assembly steps**: the definition, closing sewn seams, guesses, the step list in the tab | Medium | See Assembly steps below. |
| **Assembly instructions** in the publish app | Medium–large | See Assembly instructions below. Line-art step diagrams, parts list, pages laid out in panels. |
| **Body from measurements** | Medium | See Body below. A simple form lofted from measured rings, not an anatomical body. Shown in the Assembly tab, exported to Blender as the collider. |
| Triangulation | Medium | See Triangulation below. Pure core code, unit-tested. |
| Seam vertex matching | Small–medium | See Seam pairing below. |
| OBJ and seam JSON writer, plus the usual wiring | Small | An exporter like the others; a CLI command with a test in `Sloper.Tests.CLI`, an API tool, a menu item, a generated JSON Schema for the seam file, user docs. |
| Generated Blender Python script | Small–medium | Imports the meshes, adds sewing edges, sets up cloth and collision, runs the simulation. Cannot be tested in CI without Blender; checked by hand against a fixed Blender version. |

Rough size: placement, the Assembly tab, steps and the printed instructions are some 6–8 weeks of focused work and useful on their own. The body from measurements adds 1–2 weeks. The Blender part after it (triangulation, seam pairing, export and script) is about the size of the Garment tab, some 2–3 weeks.

## Triangulation

Clipper2's `Clipper.Triangulation` is not usable: it does not compile with FPC 3.2.2, so `src/core/clipper2/osclipper2.lpk` leaves it out, and the submodule is pinned (see the Clipper2 notes). An own mesher is needed, in the core.

Cloth simulation needs evenly sized, well-shaped triangles; plain ear clipping gives long slivers that make the cloth crease and jitter. The plan:

1. Resample each piece's seam line at an even spacing (a setting, about 10 mm by default), keeping every corner and every seam endpoint as a vertex so seams start and end on vertices.
2. Fill the inside with a regular grid (or hexagonal) of points at the same spacing, dropping points closer than half a spacing to the outline.
3. Constrained Delaunay triangulation of the outline and inner points, keeping the outline edges.
4. Optionally a few rounds of smoothing that move inner points only.

Holes (cut-outs) are inner boundaries kept as constraints. Stitch lines and markings are not meshed in the first version.

Tests: every triangle inside the outline, total area equals the outline's area within tolerance, no triangle angle below a minimum, outline vertices kept in order.

## Seam pairing

Blender's cloth sewing pulls together vertices joined by loose edges, so both sides of a seam need vertices that pair one to one.

- Take each side's run of outline vertices in the seam's direction, across all its entries and pieces, using `RunsForward` so side B runs the right way.
- Divide both sides into the same number of points, chosen from the longer side's length and the mesh spacing, at the same fractions of each side's length. The mesh's outline resampling must use these points, so seam pairing happens before triangulation: resample seam edges first, then the rest of the outline.
- Pairing by fraction of length spreads the seam's ease evenly along it, as gathering or easing would.
- A gap in a side (a waist either side of a dart) is a break in the run; each run pairs with its share of the other side by length.
- A dart's two legs pair from the apex outwards; the apex is shared.
- An edge in several seams (a neckline to a collar and a facing) gets the union of their points.
- A piece on a fold is exported whole, opened out. Its fold edge is not a seam; mirrored seams pair on both halves.

## Placement and the Assembly tab (the first step)

Planned 2026-11-17. Placement is the start of the Blender work, not the end: every later step (assembly steps, the printed instructions, the Blender script) reads it, and it is worth having on its own as a way to show how the pieces go together. The user sets it in an **Assembly** tab of the design app's side panel, after Garment, since placement is part of the pattern; a window of its own can come later if the tab proves too small.

**Why not front and back.** Labelling pieces front or back, as most pattern software does, is really an ordering in depth, and too coarse for it: a garment wraps round a body, so side panels, sleeves and gussets sit between front and back, a lining lies inside its shell, and a piece cut twice mirrored is a left and a right. What a piece needs is where it sits in 3D and which way it faces. The app cannot work this out (the reason the Garment tab dropped front and back views on 2026-11-09), so the user sets it, starting from a guess. This takes back the 2026-11-09 objection to a setting on every piece: the setting is optional, guessed, and only the assembly sheet and Blender export need it; the Garment tab stays as it is.

**Pieces relative to each other, not to a body.** Placement does not need a body: bags, hats, cases and other accessories have none, and a garment's pieces are placed the same way. The user moves each flat piece in 3D until the arrangement is an exploded view of the finished item: each piece a gap away from the pieces it is sewn to, facing the way it is sewn, right side out, in the right order in depth (front over side over back, shell over lining). The seams say which edges come together; the arrangement says from which direction. That is all Blender needs: the sewing springs close the gaps. A body, when the pattern has one (see Body), is a reference to arrange garment pieces round, never required.

**What is stored.** Each piece copy gets a placement: a rigid transform of the flat piece into 3D. A piece cut ×2 with `cut.mirrored` has two placements, the second drawn mirrored (a left and a right); a piece on a fold is placed once, opened out.

- **The assembly frame** has Blender's axes, so the export needs only a scale: X to the viewer's right as seen from the front, Y away from the viewer (towards the back), Z up, in mm. The front faces −Y. The origin is the middle of the finished item; when a body is shown, it stands with its centre line on the Z axis and its feet at Z = 0.
- **The piece frame.** The piece lies in its own plane with its drafted x along X and its drafted y (down) along −Z, the right side of the fabric facing −Y, so with no rotation a piece stands upright facing the viewer as it does on the canvas. Its origin is an **anchor**: the middle of the grainline, else the centre of the seam line's bounding box. The anchor is computed, so the placement survives measurement changes as a layout placement survives them.
- **The numbers**: `position` (x, y, z of the anchor in the assembly frame) and `rotation` (three angles in degrees, applied in a fixed order and stated in the schema; a quaternion was considered and rejected as unreadable in the file and the API). Plain numbers, not formulas, as layout placements are: placing is arranging finished pieces, not drafting. Saved with the pattern, as `placements[]` on the piece, one per copy; a piece without them is unplaced.
- **Layer**, for a lining inside its shell or interfacing on a facing, is not a separate field: it is an offset along the piece's normal, which the tab offers as a nudge ("one layer in", by the gap) so it stays one position.
- **The gap** is a pattern setting (20 mm by default), used by the guesses, Align to Seam and the layer nudge, so the arrangement keeps an even look and Blender's springs have the same distance to close everywhere.

**Defaults.** An unplaced piece is shown at a guess, not stored until the user changes it (or accepts all guesses with one command, one undo step). The guess follows the seams, not a body:

1. The piece with the largest area is placed first, upright by its grainline, facing front, at the origin.
2. Each piece sewn to a placed piece is placed as Align to Seam would place it (see Moving a piece): beside that seam, the gap away, facing the same way; pieces are taken in order of the longest seam to a placed piece. Where a piece is sewn to two placed pieces (a side panel between front and back), it is folded to sit between them.
3. A mirrored copy is placed as the mirror image of its original across the YZ plane.
4. Pieces with no seams are placed in a row below the rest, to be placed by hand.

Laid out flat this way the guess is a strip of pieces, not a closed item: it puts every piece beside its partner, and the user folds the strip round (a back behind the front, a bag's gusset round its sides). It only has to be near enough that a few moves fix it.

**Drawing.** The pieces are flat polygons, so no OpenGL is needed: each piece is projected to the screen with one affine transform (orthographic view) or per vertex (perspective), sorted back to front by the depth of its anchor and drawn with BGRABitmap, as the Garment tab draws. The back of a piece (wrong side towards the viewer) is drawn paler with its material's hatching, so a piece facing the wrong way shows at once. Each seam is drawn as a few thin connector lines between its sides (at its ends and middle, as the sheet's arrows), so the user sees what joins what, and a piece placed far from its partner, or with a seam that would cross over itself to close, stands out. The body, when shown (a toggle, on by default when the pattern has the measurements for one), is drawn faintly behind and through the pieces. Pieces overlapping in depth are allowed; the sort is per piece, and intersecting pieces may draw in the wrong order, which is acceptable for a placing tool.

**The camera.** Orbit by dragging the background (turntable about Z, so up stays up), pan with the middle button, zoom with the wheel; buttons for Front, Back, Left, Right, Top and Three-quarter views; orthographic by default, perspective as an option.

**Moving a piece.** Click to select a piece (the nearest drawn under the pointer), then:

- **Drag** moves it in the plane facing the camera, so in the front view it moves left, right, up and down, and in the top view forward, back and sideways.
- **Shift+drag** moves it towards or away from the camera.
- **Alt+drag** (or the rotate handles: three rings round the anchor, one per axis, as Blender's gizmo shows them) turns it; turns snap to 15° with Ctrl (`ssModifier`).
- **Around the centre**: a ring handle in the top view moves the piece round the vertical axis through the origin, keeping its distance from it and turning it to keep facing outward; the move most pieces of a garment or a hat need.
- **Flip** turns it to face the other way, for a piece placed inside out.
- **Fields** in Properties give position and rotation as numbers, for exact placing.
- **Align to Seam**: select a seam and one of its pieces; the piece moves so its side of the seam lies along the other side, the gap apart, so the seam closes without crossing over and the piece faces the way its partner does across the seam. A second click on Align to Seam folds it the other way (inward or outward about the seam). This places most pieces in a click or two once one is placed.

Each drag is one undo step; Reset Placement returns a piece to its guess. Keys and menu entries follow the design app's conventions.

**What it needs**, as any new definition:

- the file format and its schema, with loading of older files (no placements: all unplaced)
- document commands with undo, one drag one step (`TSetPlacementCommand`)
- the Assembly tab: drawing, camera, moving and turning
- API and MCP tools (`set_placement`, `guess_placements`), and placements in `get_object`
- design document and user documentation

The placement maths (piece to assembly frame, anchors, guesses, Align to Seam, projection) goes in a core unit (`Sloper.Core.Assembly`), without the LCL, unit-tested, so the design app, the publish app, the CLI and the exporters share it.

## Assembly steps

The exploded arrangement shows where every piece goes; sewing happens in an order (darts before side seams, a collar made up before it is set in), and instructions show that order a step at a time. Steps are part of the pattern, set in the Assembly tab, so every layout of the pattern prints the same instructions.

**What is stored.** The pattern's `assemblySteps[]`, in order, each with:

- `seams[]`: the seams sewn in this step. Each seam is in at most one step; seams in no step are listed as a warning in the tab ("Seam3 is in no step") and drawn in a last step of their own, so nothing is left out of the instructions.
- `view`: the camera the step is drawn from (azimuth, elevation, orthographic or perspective), taken from the tab's camera with Use This View; by default the previous step's, the first step's three-quarter from the front left.
- `repeat`: how many times the step is done (×2 for the second sleeve), shown once with the count; set by hand, or 2 by default when every seam in the step has a mirrored twin on the mirrored copies (the guess pairs a step for the left sleeve with the right, and shows it once).
- `note`: optional short text under the step (the user's own words, not translated).
- `detail`: optional, a seam or point to show enlarged in a round callout beside the step, for a small part (a dart point, a placket end).

Plain data like placements, saved with the pattern, every change a command with undo. Steps refer to seams by ID, so they survive renames; a deleted seam leaves the step, and a step left with no seams is deleted in the same undo step.

**What a step shows.** Pieces sewn in earlier steps are drawn **closed**, as one made-up part; the pieces this step joins are drawn **apart** at their exploded placements, with arrows for this step's seams; pieces not yet used are left out. So each step shows only what is in the sewer's hands, as flat-pack instructions show only the parts of that step.

- **Closing** moves pieces, never bends them (they are flat): for each made-up part, every piece but the first keeps its turn and is moved so that the paired points of its sewn seams (the ends and middle, as the arrows) come as close as they can, found by least squares over the moves of all its pieces, a small linear system solved in the core. Pieces with the gap set by Align to Seam close exactly; others close as near as their turns allow, and a seam that stays far open (more than a set distance) is a warning in the tab ("Seam5 does not close: turn Sleeve towards Front").
- Seams sewn in earlier steps are drawn as stitch lines along the join.
- The part made in a step is a single unit in later steps: it moves as one when closed onto the next pieces.

**Guessed steps.** A pattern with no steps gets a guess, not stored until changed (one command keeps it, one undo step): darts first, one step per piece with darts; then seams in the order the placement guess joined the pieces (the longest seam first), one step per seam, a step and its mirrored twin merged into one ×2 step. The user merges, splits and reorders from there.

**In the Assembly tab.** Below the 3D view, a step list (Step 1, Step 2, … with their seams and ×2):

- Choosing a step shows it as it will print (closed parts, pieces apart, arrows), in the same line style when Print Style is on.
- **New Step**, **Delete Step**, **Move Up**, **Move Down**, **Merge with Next**; drag seams between steps, or click a seam's connector line in the 3D view to add it to the chosen step.
- **Use This View** stores the camera in the step; the step list shows a small thumbnail.
- The whole arrangement, all pieces apart and all seams, is the **overview**, always available above Step 1.

## Assembly instructions (publish app)

Printed instructions in the manner of flat-pack furniture: an overview, a parts list, and numbered steps, drawn as line art with arrows, so they read without words and in any language.

**Pages.** Not true size, so not a cutting layout: they are laid out on the layout's paper (A4 or Letter for tiled, else A4) and printed:

- with a **tiled** layout, after the cover, when the layout's `instructions` is on (the information page the user asked for);
- as a layout of their own, output kind **Instructions**, which prints only them;
- in PDF and SVG (one file per page); DXF leaves them out, as it carries no notes.

**What the pages hold**, in order:

1. **Parts.** Every piece drawn flat and upright (as the Garment tab places it, not in 3D), each with its **tag** (A, B, C… in pattern order, or its name, a setting) and its cut count ("×2"), grouped by material. Tags are used in every step, as flat-pack instructions label their parts.
2. **Overview.** The whole arrangement, exploded, with every seam's arrows: how it all goes together, on one panel.
3. **Steps**, each in a panel: a large step number in the top left, the ×2 count beside it, the pieces (closed parts and pieces apart, as in the tab), arrows, tags in small circles on each new piece, the enlarged detail in a round callout with a line to where it is, and the note under it. Panels are laid out in a grid of 1, 2, 4 or 6 to a page (a setting, 4 by default), in reading order; a step never splits across pages.

**Style.** Line art by default, like printed furniture instructions: pieces outlined in black with a thin line, filled white on the right side and light grey on the wrong side, a soft grey shadow below each piece to show depth, stitch lines dashed, arrows solid black with filled heads. Pieces new in a step have a slightly heavier outline. A colour style (materials' colours and fills) is a setting, for screens. Tags and step numbers use the drawing font (`data/fonts`).

**Arrows.** For each seam in a step, arrows from side A to side B: one at each end and one in the middle, from the point at that fraction of side A's length to the same fraction of side B's (the pairing Seam pairing uses), with heads at both ends, curved slightly outward so arrows between pieces at the same depth do not lie across them. A dart gets one small arrow across its legs. Notches on seamed edges are drawn, so arrows and notches agree. Arrows are drawn above the pieces, dashed where they pass behind one.

**Each panel's scale** fits its own drawing (so a step showing a collar is drawn larger than one showing the whole garment); nothing is to scale, and the pages say so in the information block's place.

**The settings**, in the layout, as plain values like the rest of a layout: `instructions` on or off (tiled), panels per page, tag style (letters or names), line art or colour, whether to include the parts page and the overview, the spread (extra distance between pieces in all drawings, 0 by default), and whether the body is drawn (off by default). Views, steps, notes and details come from the pattern.

**Output.** The projection, closing and panel content come from `Sloper.Core.Assembly`; the drawing goes through the same paths as other pages, so PDF, SVG and the preview agree. The CLI prints them (`opensloper-cli export --instructions`, or a layout of the Instructions kind) and the API renders a step (`render` with `assemblyStep`), with tests.

## Body

Decided 2026-11-17: the first version builds a body from the pattern's measurements; bringing your own body comes later.

- **Built from measurements** (first version). A simple form, not an anatomical body: a torso lofted through elliptical rings at the measured heights and circumferences (neck, bust, waist, high hip, hip), with a head from `head_circumference`, and arms and legs as tapered tubes from the arm and leg circumferences and lengths, each part built only when the measurements for it are there (a skirt pattern with waist and hip gets a lower torso). Ring depth against width comes from a fixed ratio per ring, as a dress form's. Computed, never stored: it follows the measurement set and size like the rest of the pattern. Core code (`Sloper.Core.BodyForm`), unit-tested (ring circumferences match the measurements within tolerance).
- **Arms and legs** stand slightly apart (an A pose), so sleeves and trouser legs can be sewn round them without the pieces touching the torso.
- **Uses.** Drawn faintly in the Assembly tab to arrange garment pieces round; optional in the printed instructions; exported to Blender as an OBJ and used as the collider. A pattern without the measurements, or with the body turned off (an accessory), has no body, and the Blender script simulates the pieces sewn together under gravity alone, or on a simple stand the user adds.
- **Later: the user's own body.** A mesh brought from MakeHuman / MPFB, a scan or any modelling app, in the assembly frame (the script scales and moves it so its height matches `height`), used in place of the built one in the Assembly tab and in Blender. Where it is chosen (per pattern or in Preferences) is decided then.

## Blender script

Generated next to the OBJ and JSON, for one Blender version stated in its header:

1. Import the OBJ, one object per piece, named after the piece, and the body when there is one.
2. Place the pieces at their placements (guesses for unplaced pieces, with a warning), scaled from mm to m; the assembly frame has Blender's axes, so nothing else changes. Darts are left open and sewn by the simulation.
3. Add loose edges between paired seam vertices, joining the pieces into one object so sewing springs can act across pieces.
4. Add a cloth modifier with sewing on, shrinking the sewing edges; material hints set mass, stiffness and bending.
5. Add collision to the body object, when there is one, and self-collision to the garment.
6. Run the simulation for a set number of frames.

## Risks and open questions

- **Drape quality.** Blender's sewing springs pull pieces together roughly; tuning cloth settings per material may take a while, and results may look worse than expected.
- **Blender versions.** The Python API changes between releases; pin one version and say so in the user docs.
- **Mesh spacing** trades simulation speed against detail; it may want to be per material.
- **Seams that cross** (a side seam meeting an armhole seam) meet at shared corner vertices; check that they do not pull the corner two ways.
- **Testing.** Core parts (placement maths, guesses, Align to Seam, projection, body form, mesher, pairing, writer) get unit tests; the Assembly tab is checked on Xvfb; the script needs a manual check, or an optional test run when a `blender` binary is found.
- **Moving in 3D with a mouse** is the hard part of the Assembly tab. Dragging in the camera's plane plus Around the Centre and Align to Seam should cover most placing; watch how it goes before adding more handles.
- **Closing without a body.** An accessory with no collider may collapse under gravity in the simulation; the script may need to pin a piece (a bag's base) or add a simple stand. Try on the accessory examples before deciding.
- **Pieces that pass through each other** may draw in the wrong order in the tab and in the instructions, since the sort is per piece. Splitting pieces where they cross is left out unless it proves to matter.
- **Closed parts look stiff.** Flat pieces moved together show a made-up part as a box of panels, not a rounded garment, and a seam between pieces at an angle closes only along a line. For instructions that is enough, as flat-pack drawings are; the Blender simulation is the rounded look.
- **Line art must stay readable** with many pieces: the shadow and the heavier outline of new pieces carry depth; try on the tutorial patterns and an accessory before fixing line weights.
- **Placements going stale.** A piece whose shape changes a lot keeps its anchor's position and turn, which may then cross its neighbours; Align to Seam fixes it. A placement is never recalculated silently.
- **Open:** where the user's own body is chosen, when that is built.

## Suggested order

The Assembly tab comes first, then the instructions it feeds; the body and Blender follow.

1. Placement in the core (`Sloper.Core.Assembly`): the definition, file format and schema, anchors, guesses, Align to Seam, projection, with tests. Design document changes first.
2. Commands, API and MCP tools, CLI output of placements.
3. Assembly tab in the design app: drawing, camera, moving and turning, Align to Seam.
4. Assembly steps in the core (definition, closing by least squares, guessed steps), with tests; then the step list in the tab, with Use This View and the print-style preview.
5. Assembly instructions in the publish app: parts, overview and step panels, line-art style, PDF and SVG, the Instructions kind and the tiled `instructions` option, CLI and API, with tests.
6. Body from measurements in the core (`Sloper.Core.BodyForm`), with tests, shown in the Assembly tab.
7. Mesher in the core, with tests.
8. Seam pairing feeding the mesher's outline resampling, with tests.
9. OBJ and seam JSON writer (pieces and body), CLI command, schema.
10. Blender script placing pieces from their placements, checked by hand on the tutorial patterns in `docs/examples/`, garments and accessories.
11. API tool, menu item, user documentation.
12. Later: the user's own body.
