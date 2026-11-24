# Open items

Part of the [OpenSloper design](../opensloper-design-document.md). Everything not built yet, so each can become a GitHub issue; the other design files describe only what is built. When an item gets an issue, put its number here; when it is built, take it out and describe it where it belongs.

## Roadmap

1. **Web version**: the engine in WebAssembly under a TypeScript editor, with a Django server (see [Web version](web-version.md)). The Design editor is a beta at opensloper.com/design/, served by the Django site in `site/`; the Measurements (#84) and Publish (#85) apps, then accounts and subscriptions, are next. A marketplace for sellers' patterns is postponed until the editor exists, as it would make the site host user content. Encrypted sync, files encrypted in the browser with a key from the user's passphrase so the server holds blobs it cannot read, is the way to offer sync and backup later if users ask for it; whether that is still personal data under PDPA is for a lawyer, and a lost passphrase loses the files. The web editor's Save as into another folder keeps the measurement file's path as the pattern recorded it, where the desktop works it out again from the new place; the editor could do so when a granted folder holds both files.

A community release follows once the apps prove easy to use.

## To do

Agreed, but not built.

**General**

- **Translation**, for the community release (see Translation in the overview).
- **Release signing** (#17): macOS notarisation, Intel macOS builds and signed Windows programs.
- **More tutorials** (#46): moving a dart, a tote bag, a leather card wallet.
- **Help in the apps** (#32): F1 and the Help menu open the page for the current tool or dialog through a table of help IDs. Translated and versioned documentation wait for the community release.
- **Publishing the developer documentation** once the user guide has moved to docs.opensloper.com on the project's own server, putting it where GitHub Pages has the user guide now.

**Design app**

- **Transforms** (#49): a live ghost while dragging, and snapping to existing angles.
- **Rounding curved corners** (#54): `AddRoundCorner` takes only straight edges, since `TCornerArc.Compute` places the arc in closed form. Only `Compute` needs a numerical branch: Newton's method for a centre at `radius` from both edges, starting from the straight answer; no solution, a radius too big for the bend, or a tangent point past an edge's end are invalid states. Splitting and moving pieces, notches and seams onto the arc already work for curves.
- **Role styles in Preferences** (#56): overriding a role's colour, dash and weight.
- **Preferences in the web editor**: the grid's step per unit, whether the rulers show (kept between visits; for now they show at each start) and printer calibration, kept in the browser.

**Publish app**

- **A window for output and machine profiles** (#57), which are edited in the settings file for now.
- **True-shape material needed**: the estimate still packs bounding boxes; nesting needs its fold halves and mirrored pairs as shapes.
- **Raising the publish window on Wayland** (#59), which needs an `xdg-activation` token Qt 5 cannot use.

**Drape app**

- **Attaching points** (a strap's end, a button) as well as edges.
- **The user's own body**: a mesh from MakeHuman / MPFB, a scan or a modelling app, scaled so its height matches `height`.

**To try on real hardware**

- A print with the Leather output profile.
- Alt-click to cycle coincident lines on a real desktop, as some window managers take it.
- DXF-AAMA on a real cutting system, checking the layers and file-level text.
- Machine SVG and DXF on a real cutter, and whether labels need a single-stroke font.

## Open questions

- Should buttonholes become a marking role?
- Should an output profile send roles to separate files or passes, one per laser operation?
- What values does each leather marking need (skive width and depth)?
- Leather hides: is there evidence the community needs them?
- Should the draped result be shown back in the drape app, and should seams join pieces of different patterns?
- Should the drape mesh spacing be set per material?

## Future ideas

Outside the roadmap; each is taken up only when the core is solid or the community asks.

| Idea | Notes |
| --- | --- |
| Notions library | More features for the Features tab: hooks and eyes, snaps, eyelets, elastic and pockets, and a notions list for the information block |
| Multi-size output | Nested sizes on one sheet for published patterns, evaluating the pattern once per size, with a screen-only overlay for checking grading |
| Scaled body figure | The measurements app's figure scaled to the entered values, so unusual proportions and typos stand out |
| ISO 8559-1 check | Check catalogue definitions against the standard and add clause references |
| Spread tool | The chain of rotations for slash and spread in one step |
| Fabric textures | Photos of the actual fabric for fills and in Blender; nap direction for layouts |
| Leather hides | A hide's outline traced from a photo, with flaws to avoid: a sheet whose free space for nesting is its outline less its flaws |
| Materials app | An app like the measurements app keeping a list of materials and their specifications for the design and publish apps |
| Assembly instructions | An exploded arrangement of the pieces (the drape app's placements are a starting point), a list of sewing steps, and printed instructions in the manner of flat-pack furniture: a parts list, an overview and numbered line-art steps. The full plan is in commit `183e011`'s `documents/design-3d-preview-in-blender.md` |
| A feature as one object | A feature kept editable, with its settings, once the first features show which settings people change |
| Buttons at the bust | Buttonholes spaced from a fixed point, one on the bust line and the others from it, when someone asks |
| More facings | An all-in-one neck and armhole facing (two runs, one piece) and understitching lines, when people ask for them. |
