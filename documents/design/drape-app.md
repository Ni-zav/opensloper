# Drape app

Part of the [OpenSloper design](../opensloper-design-document.md). `opensloper-drape` places pattern pieces round a body in 3D and drapes them in Blender's cloth simulation. The user pages (Drape) describe it as used.

**A separate app.** The design app stays a 2D drafting app, and a garment is often made from several patterns, so placing pieces in 3D is a fourth app, not a tab of the design app. Like the publish app it imports one or more patterns, each with a measurement set and size, keeps in step with their saved files and owns its own file; nothing is written back to a pattern, so no 3D data is stored in one. The Garment tab is the quick flat look at one pattern; the drape app is for fit and drape.

**Blender does the simulation.** Writing a cloth simulator (sewing constraints, body and self-collision) is a multi-year effort, so the app writes what Blender needs and runs it: triangulated piece meshes and the body (OBJ), a JSON scene with placements, seam pairs, materials and fabrics, and a fixed Python script. The placement maths, body, mesher, seam pairing and writer are core and output code, so the CLI writes and runs the same files (`opensloper-cli drape DRAPE [-o FILE] [--spacing=MM] [--run]`).

## Placement

The 3D frame has Blender's axes, so the export needs only a scale from mm to m: X to the body's left, Y towards its back, Z up, in mm, right-handed; the body faces −Y, stands on Z = 0 with its centre line on the Z axis. Turns are anticlockwise looking from the positive end of an axis, as in Blender; this differs from the 2D convention on purpose, as it is not screen space (`Sloper.Core.Geometry3`, `Sloper.Core.DrapePlacement`).

- **A piece's frame**: drafted x along X, drafted y (down) along −Z, the fabric's right side facing −Y, so an unturned piece faces the viewer as on the canvas. Its origin, the **anchor**, is the middle of the grainline, else of the seam line's extent; it is computed, so placements survive measurement changes. A fold piece is placed opened out.
- **A placement** is `position` (the anchor) and `rotation` (degrees about X, then Y, then Z, fixed axes): Blender's XYZ Euler, so the numbers set `rotation_euler` as they are. Quaternions were rejected as unreadable in the file.
- **A mirrored copy** has its frame's x turned round; by default it is its partner's mirror image across the YZ plane.
- **The camera** orbits a target: yaw about Z (turntable, so up stays up), pitch up to 90° looking down; orthographic by default. Front, Back, Left, Right, Top and Three-quarter are fixed views.

**Align to Seam** places a copy so its side of a seam lies along the placed partner's: flat, beside it the gap apart, as sewn and opened out; or folded over onto it. A copy on the same side of the body is preferred as partner.

**Guess Placements** places the largest piece of each source upright in front of the body at waist height, each copy sewn to a placed one along its longest seam, the other of each mirrored pair as its mirror image, and the rest in a row beside the body. The guess is a strip, not a garment: the user wraps it round the body.

## The drape file

`.sdrape`, format `drape` (`Sloper.Core.DrapeFile`): the sources (as a layout's, `Sloper.Core.PatternSources`), the body (`measurements`, defaulting to the first source's set and size, or `none`; `arms: false` leaves the arms out), the gap (20 mm, how far pieces sit off the body and apart across a seam), and placements: source, piece ID, copy, `position`, `rotation` and `attached` edge IDs. A copy with no placement is left out of the export, with a problem; a placement whose piece has gone is a problem, never dropped silently. As in the publish app, the even copies of a piece cut mirrored are the mirrored ones.

## The body

A whole figure (`Sloper.Core.BodyForm`), so sleeves and trousers have arms and legs to go round, standing on Z = 0 facing −Y: a torso lofted through horizontal ellipses at the measured heights (crotch, hip, high hip, waist, bust, armpit, shoulders, neck), each sized so its ring has the measured circumference exactly; legs through ankle, calf, knee and thigh; arms hanging 20° out (`ARM_ANGLE`) through upper arm, elbow and wrist, ending in flat hands; feet pointing forwards, which shows the front from any side; and an ellipsoid head. Each part is a closed mesh facing out, overlapping where they join, which is enough for drawing and for Blender's collision.

A measurement the set lacks is a fixed share of the height (an average adult's when that is missing too), so there is always a whole figure. `neck_back_to_waist` places the waist from the neck, or the other way round, when the set measures only one. **Without arms**, the figure is a dress form with legs, for full skirts, which cannot close their side seams round arms hanging out. The user's own body shape is for later.

## The window

A 3D view beside side tabs, as the publish app: Patterns (sources, body, Arms, gap), Pieces (every copy; double-click places one by a guess), Properties (position and turns as numbers, the seams to placed pieces with Align to Seam and Fold Over Seam, and **Attached to the body** with a tick per edge), Claude and Problems.

- **Drawing** (`Sloper.Core.DrapeScene`) is flat polygons on the LCL canvas, so no OpenGL is needed. Pieces go by the depth of their middles, and each body triangle after every piece whose plane it lies on the viewer's side of, which is exact for a piece clear of the body (sorting everything by middles drew the body over a large tilted piece). A piece seen from its wrong side is paler; each seam between placed copies is three thin lines across it; attached edges are thick and green.
- **Gestures:** dragging the background turns the view, the middle button pans, the wheel zooms. Dragging a piece moves it across the view (Shift towards or away); with the modifier a sideways drag takes it round the body, facing out; a right-button drag turns it (Shift in 15° steps). Right-drag rather than Alt-drag, which Linux window managers take. Each drag is one undo step.
- Undo keeps the file's text before each change. The app keeps its tab as `drapeTab`, its recent files under `drape`, and listens on the apps' link as kind `drape`. **File → Drape…** in the design app (Ctrl+D) works as Publish… does, showing the pattern's `.sdrape` in a drape window already open or starting one.

## The mesher

`Sloper.Core.Mesher` (our own: Clipper2's triangulation does not compile with FPC 3.2.2). Cloth simulation needs even, well-shaped triangles, so a piece's seam line (opened on a fold) is resampled at an even spacing, 10 mm by default, keeping corners over 20° and any point the caller pins; the inside is a hexagonal grid at the same spacing. Points are triangulated by Delaunay's rule (Bowyer-Watson), outline edges the triangulation misses are split until they appear, so the outline is kept exactly, and three rounds of smoothing follow, never folding a triangle. The outline's points come first in the mesh, so an exporter finds them by index. Triangles run anticlockwise on screen, facing the right side out once placed.

## Seam pairing

`MeshDrape` (`Sloper.Core.DrapeMesh`) meshes every placed copy with its seams' points pinned, and lists the vertex pairs to sew.

- Both sides get points at the same fractions of their lengths, so ease is spread evenly. Every edge end is a break; between breaks points are no further apart than the spacing on the longer side. A dart pairs from the apex out.
- **Which copies sew together goes by placement:** each copy of the piece with the most on the seam takes the nearest unused copy of each other piece, so left sews to left however they were placed, and when there are too few, the copy left open is the one furthest away. A piece on both sides of a seam may sew a copy to itself (a dart, a sleeve's underarm) unless the sides share an edge (a centre back on a mirrored pair).
- A copy without a partner is a problem ("seam … is left open on a copy of …"). `DrapeSeamProblems` finds these without meshing, so the Problems tab lists them after every change.

## The export

`Sloper.Output.DrapeExport` writes three files beside the scene file, by default named after the drape: `NAME.blender.json`, `NAME.pieces.obj` and `NAME.body.obj`, plus a copy of the script as `NAME.blender.py`.

- **The scene** (format `blender`, with a schema, read by no app) names the OBJ files, lists each placed copy as an object (name, source, piece, copy, mirrored, material, colour, fabric, vertex count, `position`, `rotation`, `attached` vertices) and each seam's vertex pairs.
- **Each piece is in its own frame**, its anchor at the origin, so the placement sets the Blender object's `location` and `rotation_euler` unchanged and the piece can be moved in Blender as in the app. A mirrored copy's mesh is mirrored and its triangles reversed.
- The OBJ files are in mm with Blender's axes, imported with forward Y and up Z; vertices are in the mesher's order, which Blender's importer keeps per object, so the pairs hold. Texture coordinates are the piece's frame in metres, so a fabric photo can be laid on at real scale. Object names have control characters made spaces, so a file name cannot add lines to the OBJ.
- Unplaced copies and open seams are warnings; the files are still written.

## The Blender script

`data/blender/drape.py`, one fixed script rather than text generated per export, written for Blender 5.2.

- It imports the pieces and body, and builds **one cloth object per source** from the pieces as placed, with a loose edge per sewn pair, since Blender's sewing springs act only within one mesh; each piece keeps a vertex group, its UVs and a material of its colour. Several sources (a top and a skirt) also collide with each other.
- **Sewing goes first, without gravity:** gravity is keyed 0 for the first 40 frames and 1 after, up to 120, as pieces with gravity from the start slid off before they were sewn. The frames are baked, so the saved `NAME.blend` opens at its last frame.
- **Fabrics.** Each material's fabric has its cloth settings in the script (mass, tension, shear, bending, from Blender's presets), so the numbers live with the simulator they are for. Blender's stiffness can vary per vertex but its mass cannot, so each stiffness is the least of the cloth's fabrics with a vertex group raising it to the most, and the mass is the average.
- **Attachments.** An attached edge's vertices go in an `Attached` group, the cloth's pin group; on a body a Shrinkwrap puts them on its surface first, so a waist stays on the hips while the rest falls. With no body they are pinned where placed, so a bag hangs from its top. An attached edge cannot move, so it is placed where it sits once sewn.
- Progress lines start `OpenSloper:`. It refuses a scene of another format or a newer version. Options after `--` include `--frames`, `--sewing-frames`, `--mass`, `--quality`, `--sewing-force`, `--output` and `--no-simulate`.

Simulating takes a minute or more at the 10 mm spacing. Tests check the script's constants against the program's, the runner on a stand-in shell script, and a two-frame run where Blender is installed (CI has none).

## Running Blender

File → **Drape in Blender…** saves a new drape first, writes the export with the Preferences' spacing, finds Blender and runs it in `Sloper.Drape.BlenderDialog`: a modal window whose thread runs `RunBlender` (`Sloper.Output.BlenderRun`), showing the step or "Simulating frame N of M". Cancel ends Blender. Done, it offers **Open in Blender**; failed, it shows Blender's last lines. Without Blender the files are still written and the app says where. The Blender program, spacing and frames are preferences, not drape file settings; the CLI keeps its own options and uses the preferred Blender only without `--blender`.

**Security.** Running Blender runs Python, so what is run must not come from a drape's folder, which may be downloaded or shared.

- Blender is started from an argument list, never a shell; nothing from a drape or pattern goes into it but the scene's path and the frame count. `--factory-startup` leaves the user's add-ons and startup file out.
- **It runs the program's own script** (`TAppPaths.BlenderScriptFile`) with `--scene`, never the `NAME.blender.py` copy, which is for running by hand and which anyone who can write to the folder could change. Blender 5.2 puts neither the script's folder, the current folder nor `PYTHONPATH` on `sys.path`, so a module planted beside a drape is not imported.
- **Finding Blender never looks in the current folder** nor in a relative folder on the path (FPC's `ExeSearch` looks in the current folder first on Windows). A configured name is looked for on the path; a configured path is taken as given.
- **The script reads only the scene's folder**, taking the meshes by file name alone; it uses no `eval`, `exec` or `pickle`.
- **Open in Blender** passes `--disable-autoexec`, so no Python in the `.blend` runs.
- The Claude tab and the Automation API cannot run Blender, set the Blender program or write the script.
