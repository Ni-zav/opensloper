# The drape window

**opensloper-drape** places the pieces of one or more patterns round a body in
3D, the way they are worn, ready for draping in Blender's cloth
simulation. A drape is saved as a `.sdrape` file. It reads the saved patterns
and never changes them.

!!! note "New"
    Draping is new, and so far tried on the bodice block; other garments
    may need the settings tuned. See
    [issue #11](https://github.com/opensloper/opensloper/issues/11).

## Start a drape

In the design app, File → Drape… (++ctrl+d++) opens the drape app with the
pattern's drape file, the file of the same name ending `.sdrape`, or starts a
new one with every piece placed by a guess. It reads the saved pattern, so an
unsaved pattern is saved first, and a changed one asks whether to save. If a
drape window already shows that file, Drape… brings it to the front.

You can also open the drape app on its own: File → New from Pattern…
(++ctrl+n++) starts a drape from a pattern, and File → Open… (++ctrl+o++) takes
a drape file or a pattern.

## Parts of the window

- **The view**, on the left: the body and the placed pieces. A piece seen from its wrong side is drawn paler, so one facing the
  wrong way stands out. Thin lines cross each seam between placed pieces, at
  its start, middle and end, so you can see which edges are sewn together.
- **Tabs**, on the right, one open at a time, as in the other apps:

    | Tab | What it holds |
    | --- | --- |
    | Patterns | The patterns placed, the body and its measurements, and the gap |
    | Pieces | Every piece, placed or not; double-click one not placed to place it by a guess |
    | Properties | Where the selected piece is placed and how it is turned, and the seams that join it to placed pieces |
    | Problems | Pieces left out, pieces gone from their pattern, seams left open, and files that cannot be read |

## The body

The body is a **figure** standing on the floor: a torso, legs, arms hanging a
little out from the sides, hands, feet and a head. Its feet point to the front,
so you can tell which way it faces from any side; View → Front looks at it
from there. It is built from a measurement set: its waist, bust, hip, neck and
high hip are as round as the measurements say, at the heights they give, and
so are its thighs, knees, calves, ankles, upper arms, elbows, wrists and head;
its arms, hands and feet are as long as measured. A measurement the set does
not have is worked out from the height.

By default the figure uses the first pattern's measurements and size. On the
Patterns tab, **Choose Measurements…** picks another measurement file, **Use
the First Pattern's** goes back, and **Size** picks the size of a size table.
**No body** leaves the figure out, for bags and other accessories.

The **gap** is how far pieces are placed off the body and apart across a
seam, 20 mm by default, so the simulation has room to pull them in.

## Look around

| To | Do this |
| --- | --- |
| Turn the view round the body | Drag the background |
| Pan | Drag with the middle button |
| Zoom | The wheel, or View → Zoom In and Zoom Out (++ctrl+plus++, ++ctrl+minus++) |
| See everything | View → Fit Body (++ctrl+0++) |
| Look from a side | View → Front, Back, Left Side, Right Side, Top or Three-Quarter |

View → Perspective draws nearer things larger. Left and right are the body's
own: its left side is on your right when you look at its front.

## Place pieces

A new drape places every piece by a guess, and Pieces → Guess Placements
(++ctrl+g++) does the same for pieces not yet placed:

1. The largest piece of each pattern stands upright by its grainline in front
   of the body.
2. Each piece sewn to a placed piece goes beside it along their longest seam.
3. The second of a pair cut mirrored goes as the mirror image of the first,
   on the other side of the body.
4. Pieces with no seams wait in a row beside the body.

The guess is a strip of pieces in front of the body, not a garment: wrap it
round the body by hand. Click a piece to select it, then:

| To | Do this |
| --- | --- |
| Move it across the view | Drag it |
| Move it towards or away from you | ++shift++ and drag it |
| Take it round the body, facing out | ++ctrl++ and drag it sideways |
| Turn it | Drag it with the right button: across turns it about the vertical, up and down tips it |
| Turn it in 15° steps | ++shift++ and drag with the right button |
| Turn it to face the other way | Pieces → Flip |
| Leave it out | Pieces → Unplace, or ++delete++ |

Each drag is one step to undo. The Properties tab shows where the selected
piece is as numbers you can type: its **position** in mm (X to the body's
left, Y towards its back, Z up from the floor) and its **turn** in degrees
about X, then Y, then Z. These are the numbers Blender uses for an object's
rotation.

### Align to a seam

The Properties tab lists the seams that join the selected piece to placed
pieces. Choose one and click **Align to Seam** (or double-click it) to move the
piece so its edge lies along the other piece's edge, the gap apart, as the two
would lie sewn together and opened out. **Fold Over Seam** turns it over about
the seam instead, onto the other piece. Darts are left out: the simulation
sews them shut.

## Several patterns

A drape can hold several patterns, such as a top and a skirt, or a lining
and its shell; Patterns → **Add Pattern…** adds one and places its pieces by a
guess. Seams join pieces of the same pattern only.

The drape follows its patterns: when a pattern or measurement file is saved,
the drape reads it again within a second or two. New pieces wait on the
Pieces tab, and a placed piece that is gone from its pattern is listed under
Problems. Nothing is ever written back to a pattern.

## Drape in Blender

File → **Drape in Blender…** (the hanger on the toolbar) sews the placed
pieces round the body in [Blender](https://www.blender.org)'s cloth
simulation. It writes the files Blender needs beside the drape file (saving
a new drape first), then runs Blender in the background while a window shows
which frame it is at; **Cancel** stops it. When it is done, **Open in
Blender** opens the result, `skirt.blend`, to look round the garment. If
Blender stops with an error, the window shows its last lines.

Edit → Preferences → **Drape** sets which Blender to run (empty finds it on
the path, or where its installer puts it, and the tab says which it found),
the mesh spacing and how many frames to simulate. Without Blender the files
are still written, and the app says where.

From the command line, `opensloper-cli drape` writes the same files, beside
the drape file unless `-o` names the scene file, and `--run` runs Blender on
them:

```
opensloper-cli drape skirt.sdrape --run
```

| File | What it holds |
| --- | --- |
| `skirt.pieces.obj` | Each placed piece as a mesh of small, even triangles, made from its seam line (the seam allowance left out), opened out on a fold |
| `skirt.body.obj` | The body, when the drape has one |
| `skirt.blender.json` | Where each piece goes, its material and colour, and which vertices each seam sews together |
| `skirt.blender.py` | The script that drapes them in Blender |

`--spacing` sets how far apart the mesh's points are, 10 mm unless given:
smaller follows curves more closely but simulates more slowly. Both sides of
a seam get the same number of points, spread evenly, so any ease is spread
along the seam as easing would. Darts are left open, for the simulation to
sew shut.

Pieces that are not placed are left out, and a seam with a copy missing on
one side is left open; the command lists both as warnings, and the drape
window's Problems tab lists them as you place pieces. A copy is sewn to the
nearest copy of the piece across each seam, so a pair cut as a left and a
right is sewn left to left however you placed them; when one side has fewer
copies, the copy placed furthest from them is the one left open. Clicking the
problem selects it. The scene file is
described on the [File formats](../reference/files.md) page.

### Draping in Blender

The script is written for Blender 5.2, and may need changes for other
versions. `--run` looks for Blender on the path, and on Windows and macOS
where its installer puts it; `--blender` gives the program instead. To run
the script yourself:

```
blender --background --python skirt.blender.py
```

It joins each pattern's pieces into one cloth object, with an edge between
every pair of points a seam sews, and the body pushes the cloth away. For
the first 40 frames the seams close with no gravity, so the pieces do not
fall before they are sewn; then gravity comes on and the garment settles,
up to frame 120 (`--frames` changes this). Each piece keeps its own group
of vertices and its material's colour, and the texture coordinates are the
fabric's own size in metres, so a photo of the fabric can be laid on it at
its real scale. Open `skirt.blend` in Blender to look round the garment:
it opens at the last frame, and playing it back shows the pieces being
sewn.

Simulating takes a while: a bodice at the 10 mm spacing takes about a
minute and a half. A larger `--spacing` is quicker for a first look.

After `--` the script takes options of its own, such as
`--frames`, `--sewing-frames`, `--mass` (each vertex's, in kg),
`--quality` and `--no-simulate` (set up the scene without running it);
`blender --background --python skirt.blender.py -- --help` lists them.
