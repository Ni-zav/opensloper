# 3D preview in Blender

Notes for later work on GitHub issue #11 (3D Preview using Blender), written 2026-11-16. The design document's **Blender export (3D preview)** section stays the decision of record; this file is the working plan and estimate behind it. Fold what is decided back into the design document when the work starts.

## Goal

Export what Blender needs to drape a pattern on a body with its cloth simulation, rather than writing a simulator in OpenSloper:

- Triangulated piece meshes (OBJ)
- A JSON file with seam pairs, piece placement around the body and fabric hints
- A Blender Python script that imports the pieces, places them, creates sewing springs and runs the simulation in one step

The Garment tab stays the quick, flat look at the finished pieces; Blender is for fit and drape. The exporter lives in `src/output`, reads computed geometry only, and adds nothing to the core model in its first version.

## What already exists

- **Seams.** `TSeamObject` (`src/core/sloper.core.seam.pas`) lists side A and side B as piece and edge entries, in order along the seam, with direction (`RunsForward`, `Reversed`), ease and lengths. A side may span pieces (a sleeve cap to a front and a back armhole) and have gaps.
- **Darts are seams** whose two sides are adjacent edges of one piece meeting at the apex. Blender can sew them shut like any other seam, so the export keeps darts open rather than closing them as the Garment tab does.
- **Folds.** A piece cut on a fold already gives its whole, opened-out outline (the half and its mirror image).
- **Seam lines.** The Garment builder (`src/core/sloper.core.garment.pas`) works on seam lines, not cutting lines, which is what the mesh is made from. The seam allowance is left out of the mesh.
- **Materials** give a place to hang fabric hints (weight, stretch, stiffness) later.

## New work

| Part | Size | Notes |
|---|---|---|
| Triangulation | Medium | See Triangulation below. Pure core code, unit-tested. |
| Seam vertex matching | Small–medium | See Seam pairing below. |
| OBJ and seam JSON writer, plus the usual wiring | Small | An exporter like the others; a CLI command with a test in `Sloper.Tests.CLI`, an API tool, a menu item, a generated JSON Schema for the seam file, user docs. |
| Generated Blender Python script | Small–medium | Imports the meshes, adds sewing edges, sets up cloth and collision, runs the simulation. Cannot be tested in CI without Blender; checked by hand against a fixed Blender version. |
| **Placing pieces around a body** | **Large** | See Placement below. Needs a new saved definition per piece. |
| A body | Large, or skip it | See Body below. |

Rough size: a first working version (triangulation, seam pairing, export and script, with the user bringing a body and nudging pieces in Blender) is about the size of the Garment tab, some 2–3 weeks of focused work. Stored placement adds several weeks; a parametric body is a project of its own.

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

## Placement

The app cannot tell a front from a back (the reason the Garment tab dropped front and back views on 2026-11-09), so it does not know where a piece goes on a body.

**First version: no stored placement.** Pieces are laid flat on a vertical cylinder around the body, in pattern order, each upright by its grainline, at the height of its drafted position. The user moves and turns them in Blender before running the simulation; the script stops after placing so they can do so, and a second step runs the sewing.

**Later: a placement per piece**, saved with the pattern. Something like a side (front, back, left, right, sleeve), a height and a turn, with sensible defaults guessed from the seams (pieces sewn to each other go next to each other). This is a new definition, so it needs:

- the file format and its schema, with loading of older files
- document commands with undo
- a panel or Properties fields to set it
- API and MCP tools
- design document and user documentation

## Body

- **First version:** the user brings a body (MakeHuman / MPFB, or any mesh) and the script uses the object named in its settings as the collider.
- **Later, maybe:** scale a base body from the pattern's measurements (bust, waist, hip, height, …). A body built from measurements is a large project of its own and is left out of these plans.

## Blender script

Generated next to the OBJ and JSON, for one Blender version stated in its header:

1. Import the OBJ, one object per piece, named after the piece.
2. Place the pieces (the cylinder of the first version, or stored placement later).
3. Add loose edges between paired seam vertices, joining the pieces into one object so sewing springs can act across pieces.
4. Add a cloth modifier with sewing on, shrinking the sewing edges; material hints set mass, stiffness and bending.
5. Add collision to the body object and self-collision to the garment.
6. Run the simulation for a set number of frames.

## Risks and open questions

- **Drape quality.** Blender's sewing springs pull pieces together roughly; tuning cloth settings per material may take a while, and results may look worse than expected.
- **Blender versions.** The Python API changes between releases; pin one version and say so in the user docs.
- **Mesh spacing** trades simulation speed against detail; it may want to be per material.
- **Seams that cross** (a side seam meeting an armhole seam) meet at shared corner vertices; check that they do not pull the corner two ways.
- **Testing.** Core parts (mesher, pairing, writer) get unit tests; the script needs a manual check, or an optional test run when a `blender` binary is found.

## Suggested order

1. Mesher in the core, with tests.
2. Seam pairing feeding the mesher's outline resampling, with tests.
3. OBJ and seam JSON writer, CLI command, schema.
4. Blender script, checked by hand on the tutorial patterns in `docs/examples/`.
5. API tool, menu item, user documentation.
6. Stored placement (a separate piece of work, with design document changes first).
