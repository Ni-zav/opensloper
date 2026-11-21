# The Features tab

The **Features** tab in the side panel adds a sewing detail to the pattern in
one step. Choose the feature, select where it goes on the canvas, check its
settings and click **Apply**. The feature is made of the ordinary points,
edges, notches and allowances you could draw yourself, so afterwards you can
change any of them as you like. One **Undo** takes the whole feature off
again.

The tab has two features, the zip and the dart. More are planned, such as
buttons and buttonholes, pockets and facings.

## Zip

A zip goes along an edge of a piece, such as a centre back or a side seam.
The tutorial [Adding a zip](../tutorials/zip.md) puts one in a skirt step
by step.

1. Open the **Features** tab and choose **Zip**.
2. Click the edge on the canvas. The tab says **Along** and the edge's name.
3. Check the settings, then click **Apply**.

| Setting | What it does |
| --- | --- |
| Style | **Centred**: topstitched either side of the seam. **Invisible**: sewn from the inside, so nothing shows and no topstitching is added. **Lapped**: one side laps over the zip, stitched down beside it and across at the stop. **Fly front**: the side laps over by the fly's width, stitched down and curving in to the stop as a J, with a fly shield behind the zip |
| Length | How long the opening is. It starts as `#zip_length`, a [variable](formulas.md) that the first zip adds at 20 cm, so every zip in the pattern can share it; type a number or another formula for a different length |
| Starts from | Which end of the edge the opening starts at, such as the waist |
| Allowance along the zip | The seam allowance along the opening, usually wider than the rest of the seam so the zip tape has room. For a fly front it is the **fly extension**, which folds back to make the fly |
| Topstitching from the seam | How far in from the seam the topstitching runs: either side of a centred zip, the lap's width for a lapped zip, the fly's width for a fly front |
| Fly shield width | For a fly front, how wide the shield is once folded |

Each style starts with its own widths, in the pattern's unit: a centred zip
is stitched 7 mm from the seam with a 20 mm allowance, a lapped zip 10 mm
from it, and a fly front 30 mm from it with a 40 mm extension and a 40 mm
shield.

**Apply** then:

- adds a point, **ZipStop**, where the zip ends, the length from the end you
  chose;
- splits the edge there, so the opening and the rest of the seam are edges of
  their own, and every piece that uses the edge takes both parts;
- gives the opening its own allowance (see
  [Seam allowance](pieces.md#seam-allowance));
- notches every piece at the stop, so the two sides match;
- adds the topstitching as stitch lines inside each piece: along the opening
  for a centred zip; along it and across at the stop for a lapped zip; down
  at the fly's width and curving in to the stop for a fly front, where the
  straight part runs down a construction guide the width from the seam;
- for a fly front, adds a **FlyShield** piece to the right of the pattern:
  the zip's length and 2 cm more, cut on the fold, so it stays as long as
  the zip.

### Lapped zips and fly fronts

Only one side of a lapped zip or a fly is stitched on the outside. Apply the
style to the side that laps over, and **Invisible** to the other side, which
then gets its stop, notch and allowance with no topstitching. A front cut
twice as a mirrored pair needs only one fly: cut both with the extension, and
stitch the J on the side that laps over, as the line on the pattern shows.

A zip longer than its edge is refused, and the status bar says why.

When the edge is in a [seam](pieces.md#seams) with another piece's edge, the
status bar reminds you that the other side needs a zip too: select that edge
and click **Apply** again. Both use `#zip_length`, so they stay the same
length. A back cut twice as a mirrored pair needs only one zip, as both
copies are the same piece.

## Dart

A dart goes into an edge of one piece, such as a waist or a shoulder, and
runs into the piece to its point. The tutorial
[Adding a dart](../tutorials/darts.md) puts one in a skirt step by step.

1. Open the **Features** tab and choose **Dart**.
2. Click the edge on the canvas. The tab says **In** and the edge's name.
   To run the dart to a point you have drafted, such as the bust point,
   ++shift++ and click that point too.
3. Check the settings, then click **Apply**.

| Setting | What it does |
| --- | --- |
| Middle | How far along the edge the middle of the dart is, from the end chosen under **Starts from**. Leave it empty for halfway |
| Starts from | Which end of the edge the middle is measured from |
| Width | How wide the dart is at the edge: 2 cm to start with |
| Depth | How far the dart runs into the piece, square to the edge: 9 cm to start with. With a point selected, the dart runs to the point instead |
| Hole back from the point | How far back from the point the hole marking the dart's end goes, along its centre line: 1 cm to start with, 0 on the point, empty for no hole |
| Pressed towards | Which end of the edge the dart is pressed towards once sewn, which shapes its cap (below) |

**Apply** then:

- adds a point, **DartMid**, at the middle, and two points, **DartLeg**,
  half the width either side of it along the edge, so on a curved waist they
  stay on the curve;
- adds **DartApex**, the dart's point, at the depth from DartMid, unless you
  selected a point for it;
- adds the two legs, from the edge to the point, and splits the edge at both
  legs: in the piece's outline the legs take the place of the edge between
  them, which stays as a construction line;
- adds a [seam](pieces.md#seams) between the legs, named **Dart**, which
  checks they match and lets [the Garment tab](garment.md) close the dart;
- notches the piece at both legs;
- adds a hole near the point and draws the dart's centre line as a fold
  line;
- gives the dart a cap (below).

The dart follows what it was made from: change the width or depth formula
of the points, or move the point it runs to, and the legs, seam, hole and
cap follow.

A dart wider than its edge, or whose legs run past an end of it, is refused,
as is one with no depth, one whose point is outside the piece, one whose
legs would cross another edge of the piece, and one in a fold. The status
bar says why.

### The dart's cap

Once a dart is sewn and pressed to one side, the seam allowance across it has
to be the shape of the folded dart: a small point that sticks out from the
cutting line. Cut straight across instead, the folded dart would come up
short of the seam. The cap is worked out the way you would by hand: the dart
is folded closed and pressed, the cutting line is drawn across it, and the
dart is opened out again. Pressed one way or the other, the cap is the same
for a dart in a straight edge with the same allowance either side, and
differs when they are not.

A dart you drew yourself can have a cap too, as long as a seam joins its two
legs: select the piece, and under **Cap on** and the seam's name choose
which leg's side it is pressed towards, or None.

## In scripts and with Claude

Each feature is a method of the [Automation API](../scripting/index.md),
named `feature_` and the feature: `feature_zip` puts a zip along an edge
and `feature_dart` a dart in one, with the same settings as the tab, so the
Claude tab and other assistants can add them too, and `set_dart_cap` gives
a dart drawn by hand its cap. See the
[Automation API reference](../reference/api.md).
