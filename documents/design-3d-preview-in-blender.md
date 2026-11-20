# 3D preview in Blender

Notes for later work on GitHub issue #11 (3D Preview using Blender), written 2026-11-16. The design document's **Drape app and Blender export** section stays the decision of record; this file is the working plan and estimate behind it. Fold what is decided back into the design document when the work starts.

**Changed 2026-11-18.** The 2026-11-17 plan put placement in an Assembly tab of the design app, with assembly steps and printed flat-pack style instructions as the first steps. All of that is dropped from this plan: the design app stays a 2D drafting app, and a garment is often made from several patterns, which one pattern's tab cannot place together. Placement moves to a **separate drape app** (`opensloper-drape`) that imports one or more patterns, as the publish app does, places their pieces on a generic body, and does the Blender generation and processing. Assembly steps and instructions are a good idea for later (see Later).

## Goal

Drape pieces from one or more patterns on a body with Blender's cloth simulation, rather than writing a simulator in OpenSloper. The drape app writes what Blender needs and runs it:

- Triangulated piece meshes (OBJ)
- A JSON file with seam pairs, each piece's placement in 3D and fabric hints
- The body (OBJ)
- A Blender Python script that imports the pieces and body, places them, creates sewing springs and runs the simulation in one step

The design app's Garment tab stays the quick, flat look at one pattern's finished pieces; the drape app is for fit and drape. Nothing in the design app changes, and no 3D data is stored in a pattern.

## The drape app

A fourth GUI app beside measurements, design and publish (`opensloper-drape`, in `src/drape/`, named 2026-11-18). It follows the publish app's pattern:

- **Its own file**, as a layout is the publish app's: it lists its **sources**, each a pattern with a measurement set and size, with IDs from the file's own never-reused counter, plus the body and each piece copy's placement. Placements refer to a piece by source and piece ID, so they survive measurement changes and edits, and are plain numbers, not formulas. Information flows one way: measurements → patterns → 3D file; nothing is written back to a pattern.
- **Keeping in step** with saved patterns as the publish app does (checksum polling, a changed file loaded once it reads the same twice); new pieces appear unplaced, a deleted piece is a problem, never dropped silently.
- **Shared code**: it links the core and the output layer, evaluates patterns itself, and uses the apps' link (`Sloper.API.AppLink`) for preferences and for a menu item in the design app that opens the current pattern in it, as Publish… does.
- A thin UI, as `src/ui`: the placement maths, body, mesher, seam pairing and writer are core or output code, so the CLI and tests use them without the app.

**Window.** A 3D view of the body and the placed pieces, a list of sources and pieces (placed and unplaced, as the publish app's tray), Properties for the selected piece (position, rotation as numbers) and the Blender settings, and commands to export and run Blender.

## What already exists

- **Seams.** `TSeamObject` (`src/core/sloper.core.seam.pas`) lists side A and side B as piece and edge entries, in order along the seam, with direction (`RunsForward`, `Reversed`), ease and lengths. A side may span pieces (a sleeve cap to a front and a back armhole) and have gaps.
- **Darts are seams** whose two sides are adjacent edges of one piece meeting at the apex. Blender can sew them shut like any other seam, so the export keeps darts open rather than closing them as the Garment tab does.
- **Folds.** A piece cut on a fold already gives its whole, opened-out outline (the half and its mirror image).
- **Seam lines.** The Garment builder (`src/core/sloper.core.garment.pas`) works on seam lines, not cutting lines, which is what the mesh is made from. The seam allowance is left out of the mesh.
- **Materials** give a place to hang fabric hints (weight, stretch, stiffness) later.
- **Measurements**: the catalogue (`data/measurement-catalogue.json`) has the heights and circumferences a simple body needs (`height_*`, `neck_circumference`, `bust_circumference`, `waist_circumference`, `hip_circumference`, `upper_arm_circumference`, `thigh_circumference`, `head_circumference`, …).
- **The publish app** shows how an app with sources, a tray, keeping in step and its own file is built.

## New work

| Part | Size | Notes |
|---|---|---|
| **The drape app**: the file format and schema, sources and keeping in step, document commands with undo, the window | Medium–large | Much is the publish app's shape; see The drape app. |
| **Placement on the body**: the definition, guesses, the 3D view, camera, moving and turning | Large | See Placement. Projection and drawing are simple (flat pieces and one body mesh, no OpenGL); handling moves and turns well is the work. |
| **Generic body** | Medium | See Body. |
| Triangulation | Medium | See Triangulation. Pure core code, unit-tested. |
| Seam vertex matching | Small–medium | See Seam pairing. |
| OBJ and seam JSON writer, plus the usual wiring | Small | An exporter like the others; a CLI command with a test in `Sloper.Tests.CLI`, a generated JSON Schema for the drape file and the seam file, user docs. |
| Generated Blender Python script and running Blender | Small–medium | Imports the meshes, adds sewing edges, sets up cloth and collision, runs the simulation. Cannot be tested in CI without Blender; checked by hand against a fixed Blender version. |

Rough size: the app with placement and the body is some 4–6 weeks of focused work; the Blender part after it (triangulation, seam pairing, export and script) is about the size of the Garment tab, some 2–3 weeks.

## Placement

The user places each piece copy on or near the body, facing the way it is worn, right side out, a little off the body so the simulation can pull it in. The seams say which edges come together; the placement says from which direction. The sewing springs close the gaps.

**What is stored.** Each piece copy gets a placement: a rigid transform of the flat piece into 3D. A piece cut ×2 with `cut.mirrored` has two placements, the second drawn mirrored (a left and a right); a piece on a fold is placed once, opened out. A piece without one is unplaced and left out of the export, with a warning.

- **The frame** has Blender's axes, so the export needs only a scale: X to the body's left (the viewer's right seen from the front), Y towards the back, Z up, in mm. The body faces −Y, stands with its centre line on the Z axis and its feet at Z = 0.
- **The piece frame.** The piece lies in its own plane with its drafted x along X and its drafted y (down) along −Z, the right side of the fabric facing −Y, so with no rotation a piece stands upright facing the viewer as it does on the canvas. Its origin is an **anchor**: the middle of the grainline, else the centre of the seam line's bounding box. The anchor is computed, so the placement survives measurement changes.
- **The numbers**: `position` (x, y, z of the anchor) and `rotation` (three angles in degrees about X, then Y, then Z, about the fixed axes: Blender's XYZ Euler order, decided 2026-11-20; a quaternion was considered and rejected as unreadable in the file).
- **Layers** (a lining inside its shell) are an offset along the piece's normal; the app offers a nudge ("one layer in") by the **gap**, a file setting (20 mm by default) also used by the guesses and Align to Seam.

**Guesses.** An unplaced piece can be guessed (one command for all, one undo step):

1. The piece with the largest area of each source is placed upright by its grainline in front of the body, the gap off it, at the height of its middle.
2. Each piece sewn to a placed piece is placed as Align to Seam would place it, in order of the longest seam to a placed piece.
3. A mirrored copy is placed as the mirror image of its original across the YZ plane.
4. Pieces with no seams are placed in a row beside the body, to be placed by hand.

The guess is a strip in front of the body, not a closed garment; the user wraps it round. It only has to be near enough that a few moves fix it.

**Drawing.** The pieces are flat polygons and the body one mesh, so no OpenGL is needed: each is projected (orthographic, or perspective as an option) and drawn back to front with BGRABitmap, the body's triangles shaded by their normal. The back of a piece (wrong side towards the viewer) is drawn paler with its material's hatching, so a piece facing the wrong way shows at once. Each seam is drawn as a few thin connector lines between its sides (at its ends and middle), so a piece placed far from its partner, or a seam that would cross over itself to close, stands out. Pieces overlapping in depth are allowed; intersecting pieces may draw in the wrong order, which is acceptable for a placing tool.

**The camera.** Orbit by dragging the background (turntable about Z, so up stays up), pan with the middle button, zoom with the wheel; buttons for Front, Back, Left, Right, Top and Three-quarter views.

**Moving a piece.** Click to select a piece, then:

- **Drag** moves it in the plane facing the camera; **Shift+drag** towards or away from the camera.
- **Alt+drag** (or rotate rings round the anchor, one per axis) turns it; turns snap to 15° with Ctrl (`ssModifier`).
- **Around the body**: a ring handle in the top view moves the piece round the Z axis, keeping its distance and turning it to keep facing outward; the move most garment pieces need.
- **Flip** turns it to face the other way, for a piece placed inside out.
- **Fields** in Properties give position and rotation as numbers.
- **Align to Seam**: select a seam and one of its pieces; the piece moves so its side of the seam lies along the other side, the gap apart, facing the way its partner does across the seam. A second click folds it the other way about the seam.

Each drag is one undo step; Reset Placement returns a piece to its guess.

**Several patterns.** Pieces from different sources are placed and simulated together (a top over a skirt, a lining pattern inside a shell), colliding with each other, but seams only join pieces of the same pattern. A seam across patterns is not in the first version.

The placement maths (piece to frame, anchors, guesses, Align to Seam, projection) goes in a core unit (`Sloper.Core.DrapePlacement`), without the LCL, unit-tested.

## Body

A **generic body**: a simple form, not an anatomical body, sized from a measurement set. **Built 2026-11-20** first as a dress form (the torso on a stand), then the same day as the whole figure below: torso, legs, feet pointing forwards, arms hanging 20° out with hands, and a head with a nose. See the design document.

- **Built from measurements** (first version). A torso lofted through elliptical rings at the measured heights and circumferences (neck, bust, waist, high hip, hip), with a head from `head_circumference`, and arms and legs as tapered tubes from the arm and leg circumferences and lengths. A part whose measurements are missing is built from fixed proportions of `height`, so there is always a whole body. Ring depth against width comes from a fixed ratio per ring, as a dress form's. Core code (`Sloper.Core.BodyForm`), unit-tested (ring circumferences match the measurements within tolerance).
- **Which measurements**: the file's body takes a measurement set and size of its own, by default the first source's.
- **Arms and legs** stand slightly apart (an A pose), so sleeves and trouser legs can be sewn round them without touching the torso.
- **No body** is an option, for accessories: the pieces are simulated under gravity alone, or on a simple stand the user adds.
- **Later: the user's own body.** A mesh from MakeHuman / MPFB, a scan or any modelling app, scaled so its height matches `height`.

## Triangulation

**Built 2026-11-20** as `Sloper.Core.Mesher`, as below (see the design document). Clipper2's `Clipper.Triangulation` is not usable: it does not compile with FPC 3.2.2, so `src/core/clipper2/osclipper2.lpk` leaves it out, and the submodule is pinned (see the Clipper2 notes). An own mesher is needed, in the core.

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
- A piece cut ×2 is two copies, each with its own vertices; a seam joins the copies placed on the same side.

## Blender script and running it

The script is generated next to the OBJ and JSON, for one Blender version stated in its header:

1. Import the OBJ, one object per piece copy, named after its source and piece, and the body when there is one.
2. Place the pieces at their placements, scaled from mm to m; the frame has Blender's axes, so nothing else changes. Darts are left open and sewn by the simulation.
3. Add loose edges between paired seam vertices, joining each pattern's pieces into one object so sewing springs act across pieces.
4. Add a cloth modifier with sewing on, shrinking the sewing edges; material hints set mass, stiffness and bending.
5. Add collision to the body, and self-collision to the garment.
6. Run the simulation for a set number of frames and save the `.blend` file.

**Running Blender.** With a Blender binary set in Preferences (or found on the path), the app runs the script in the background (`blender --background --python …`), shows its progress and errors, and opens the saved `.blend` in Blender when done; without one it writes the files and says how to run them. The CLI does the same from a drape file (`opensloper-cli drape`), writing the files and running Blender when asked. Whether the app also shows the draped result in its own view (by reading the simulated mesh back) is open.

## Risks and open questions

- **Drape quality.** Blender's sewing springs pull pieces together roughly; tuning cloth settings per material may take a while, and results may look worse than expected.
- **Blender versions.** The Python API changes between releases; pin one version and say so in the user docs.
- **Mesh spacing** trades simulation speed against detail; it may want to be per material.
- **Seams that cross** (a side seam meeting an armhole seam) meet at shared corner vertices; check that they do not pull the corner two ways.
- **Testing.** Core parts (placement maths, guesses, Align to Seam, projection, body form, mesher, pairing, writer) get unit tests; the app is checked on Xvfb; the script needs a manual check, or an optional test run when a `blender` binary is found.
- **Moving in 3D with a mouse** is the hard part of the app. Dragging in the camera's plane plus Around the Body and Align to Seam should cover most placing; watch how it goes before adding more handles.
- **Closing without a body.** An accessory may collapse under gravity in the simulation; the script may need to pin a piece (a bag's base) or add a simple stand. Try on the accessory examples before deciding.
- **Placements going stale.** A piece whose shape changes a lot keeps its anchor's position and turn, which may then cross its neighbours; Align to Seam fixes it. A placement is never recalculated silently.
- **Open:** whether the draped result is shown back in the app; seams across patterns.

## Suggested order

1. Design document changes first.
2. Placement in the core: the definition, the drape file format and schema, anchors, guesses, Align to Seam, projection, with tests.
3. Body from measurements in the core (`Sloper.Core.BodyForm`), with tests.
4. The drape app: sources and keeping in step, commands with undo, the 3D view, camera, moving and turning, Align to Seam; the design app's menu item to open a pattern in it.
5. Mesher in the core, with tests.
6. Seam pairing feeding the mesher's outline resampling, with tests (built 2026-11-20, `Sloper.Core.DrapeMesh`).
7. OBJ and seam JSON writer (pieces and body), CLI command, schemas (built 2026-11-20, `Sloper.Output.DrapeExport`, `opensloper-cli drape`; see the design document). Seams left open show in the app's Problems tab (built 2026-11-20).
8. Blender script and running Blender from the app, checked by hand on the tutorial patterns in `docs/examples/`, garments and accessories.
9. User documentation, packaging the fourth app.
10. Later: the user's own body.

## Later

- **Assembly steps and instructions** (the 2026-11-17 plan, set aside 2026-11-18). An exploded arrangement of the pieces, a list of steps (which seams are sewn in each, from which view), and printed instructions in the manner of flat-pack furniture: a parts list, an overview and numbered line-art steps with arrows between the edges sewn together. The drape app's placements are a natural starting point for the arrangement when this is taken up. The 2026-11-17 version of this file (commit `183e011`) has the full plan.
- **The user's own body** (see Body).
