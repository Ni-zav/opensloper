# The Features tab

The **Features** tab in the side panel adds a sewing detail to the pattern in
one step. Choose the feature, select where it goes on the canvas, check its
settings and click **Apply**. The feature is made of the ordinary points,
edges, notches and allowances you could draw yourself, so afterwards you can
change any of them as you like. One **Undo** takes the whole feature off
again.

For now the tab has one feature, the zip. More are planned, such as buttons
and buttonholes, pockets and facings.

## Zip

A zip goes along an edge of a piece, such as a centre back or a side seam.

1. Open the **Features** tab and choose **Zip**.
2. Click the edge on the canvas. The tab says **Along** and the edge's name.
3. Check the settings, then click **Apply**.

| Setting | What it does |
| --- | --- |
| Style | **Centred**: topstitched either side of the seam. **Invisible**: sewn from the inside, so nothing shows and no topstitching is added |
| Length | How long the opening is. It starts as `#zip_length`, a [variable](formulas.md) that the first zip adds at 20 cm, so every zip in the pattern can share it; type a number or another formula for a different length |
| Starts from | Which end of the edge the opening starts at, such as the waist |
| Allowance along the zip | The seam allowance along the opening, usually wider than the rest of the seam so the zip tape has room |
| Topstitching from the seam | For a centred zip, how far in from the seam the topstitching runs |

**Apply** then:

- adds a point, **ZipStop**, where the zip ends, the length from the end you
  chose;
- splits the edge there, so the opening and the rest of the seam are edges of
  their own, and every piece that uses the edge takes both parts;
- gives the opening its own allowance (see
  [Seam allowance](pieces.md#seam-allowance));
- notches every piece at the stop, so the two sides match;
- for a centred zip, adds the topstitching as a stitch line inside each piece,
  along the opening.

A zip longer than its edge is refused, and the status bar says why.

When the edge is in a [seam](pieces.md#seams) with another piece's edge, the
status bar reminds you that the other side needs a zip too: select that edge
and click **Apply** again. Both use `#zip_length`, so they stay the same
length. A back cut twice as a mirrored pair needs only one zip, as both
copies are the same piece.
