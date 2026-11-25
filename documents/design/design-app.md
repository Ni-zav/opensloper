# Design app

Part of the [OpenSloper design](../opensloper-design-document.md). `opensloper-design` drafts patterns. The user pages (Design) and the generated reference pages describe it as used; this file keeps the decisions.

## Evaluator

`Sloper.Core.Evaluator` turns definitions into coordinates in dependency order and records why anything fails instead of crashing.

**Graph.** Measurements (`@key`), variables and draft objects (by ID) are nodes. A node depends on its direct inputs and every reference in its formulas. Nodes are sorted topologically (Kahn's algorithm) and evaluated in order. Patterns are small, so `Evaluate` rebuilds and recomputes everything on every change.

**Cycles.** `TPattern.SetFormula` refuses an edit that would make a cycle, naming both nodes. A loaded file can still hold one: nodes on it become errors and their readers are blocked, told apart in one pass (`TEvaluator.MarkCycles`, Tarjan's algorithm with its own stacks). Graph walks use explicit lists rather than recursion, since a file can make a chain as long as it likes.

| State | Meaning | Example | Display |
| --- | --- | --- | --- |
| Valid | Computed fine |  | Normal |
| Error | Formula problem | Unknown name, divide by zero, a measurement the set lacks | Red, message on hover |
| Invalid | Geometry impossible | Parallel lines, a distance past the end of a curve | Red, message on hover |
| Blocked | An input failed | Depends on an invalid point | Faded orange, "blocked by point C" |

Each node keeps its last good value, drawn ghosted while it fails, so the drawing has no sudden holes. A math error inside one node (an overflow as cm becomes mm) makes that node invalid and never ends the evaluation.

**Editing API.** `TPattern` (`Add…`, `SetFormula`, `Rename`, `Delete`) reports refusals in `LastError`, `LastErrorField` and `LastErrorPos`; `Delete` is refused while others use the object. `TPattern` is the one entry point; operations that rework existing objects live in their own units behind its methods (`Sloper.Core.TypeChange`, `Sloper.Core.PointMerge`, through a small editing kernel at the end of the class), and the materials are a `TPatternMaterials`. Operations that make new objects stay in `TPattern`.

**Edges as segments.** Every edge keeps its geometry as straight or cubic segments, so length, positions along it, splitting and crossings work the same for every kind. An extended edge adds a ray off each end along its tangent. Curve–line crossings solve the cubic; curve–circle splits the curve where its distance from the centre turns; curve–curve halves both while near enough to meet, down to 0.0001 mm.

## Names and IDs

References are stored as IDs and shown as names, so renaming changes one field and never breaks a formula.

**Formulas.** The user types names (`Line_A_B.length + @waist/4 + #ease`) with completion; on commit the ID form is stored (`{12}.length + @waist/4 + {3}`). Unknown names are refused as typed.

**IDs** are positive integers from one counter per pattern, shared by every kind of object. The counter is saved as `nextId` and only goes up, so an ID is never reused, not after delete, undo, save or reopen; layouts and drapes refer to pieces by ID, and a reused one would quietly put another piece in its place. IDs are read as 32-bit integers up to `JSON_MAX_ID`; only a file made to sit at that limit gets the lowest free ID for a new object. Pasted and imported objects get fresh IDs. UUIDs were rejected: only needed across files, and they would make formulas long and unreadable. Measurements are referred to by key, so any file with the same keys works.

**Name rules:** letters, digits and underscore, not starting with a digit (dashes and dots clash with formulas); function names and keywords reserved; case kept but compared case-insensitively; unique per namespace (draft objects, `#` variables, `@` measurements, materials). Automatic names count like spreadsheet columns (`A` … `Z`, `AA` …) and never contain digits, so a trailing number always means a copy. An edge is named after its ends (`Line_A_B`) unless named. Clashes from paste or import append the next free number (`A` → `A2`, a copy of `A2` is `A3`) and are reported. Undo and redo never fail or prompt.

## Formula engine

A small recursive-descent parser of our own (`Sloper.Core.Formula`, on `Sloper.Core.FormulaLexer`): our syntax is small enough that it is less code than wrapping TFPExpressionParser, whose error positions, accepted syntax and exceptions did not fit.

**Syntax.** Numbers with `.` and an optional unit (`2in`), `+ - * /`, `^` (right-associative, tighter than unary minus, so `-2^2 = -4`), brackets, the functions on the generated Formula functions page, and references `@measurement`, `#variable`, `Object.property`, `Repeat[index].property`. Angles are degrees.

**Failures are states.** A parse error gives a message and position in the text as typed; evaluation errors set `ErrorMessage` and `ErrorPos`. FPU exceptions are masked and infinite or NaN results become errors. A formula that fails to parse keeps its text.

**Depth is limited** to 256 levels (`MAX_FORMULA_DEPTH`), since the parser, evaluation and freeing recurse and a crafted file could otherwise overflow the stack.

## Pattern units

**A pattern has one unit, mm, cm or inches, and every number in its formulas is in that unit.** In an inch pattern `@waist/4 + 1` adds one inch. The unit is the file's `units`, taken from Preferences when the pattern is made.

**Formulas are worked out in the pattern unit.** Every length a formula reads arrives in it: measurements (stored in mm, converted as read), variables and properties such as `.length`. Angles are never converted. Where a result becomes geometry it is scaled to mm, so **geometry, computed state, the canvas and every export stay in mm**. In code, the context's `LengthScale` converts lengths as read, and length fields are read with `EvalLength`.

**What the user sees.** Properties, status bar, rulers, grid, read-outs and drag rounding (0.1 mm, 0.1 cm, 0.01 in) use the pattern unit, and new objects start at round values per unit (`STARTING_LENGTHS`). In the Automation API formulas are in the pattern unit and reported positions in mm. The Measurements tab stays in mm, since it edits the measurement file.

**Unit suffixes.** `400mm`, `1.5cm` or `2in` keep their meaning in any pattern and are never rewritten by a conversion. **A unit where none belongs is refused** (`Sloper.Core.UnitCheck`): a suffixed length in an angle or plain-number field (`45mm`), inside `sin` and the like, or added to a plain number. A formula's power of length is worked out from what is certain (suffixed numbers, measurements, length properties); only formulas with a suffix are judged, and loading a file does not check.

**Converting a pattern** (Tools → Convert Pattern Units…, `Sloper.Core.UnitConvert`) rewrites only lengths (`400` mm → `15.75` in), so each plain number's power of length must be known: the field fixes the result's power (`FieldUnitKind`), and the expression tree gives linear equations between the unknowns, solved by Gauss–Jordan elimination. Numbers still open (`400 * 2` in a length field) are listed for the user to choose. One undo step; geometry moves only by rounding.

## Operations

Nine point operations and the edge types cover bodice, skirt and trouser blocks; circles, arcs, rounded corners and offset edges were added for accessories. Many of Valentina's ~30 tools become special cases once formulas read properties such as `{4}.angle`. Every operation, its members and properties are on the generated Operations and objects page, from `Sloper.Core.OperationInfo`, which tests hold to the code.

**Round Corner** keeps the closed-form construction for two straight edges. When a curve is involved, the engine starts with the corner's end tangents and searches for an intersection of the two inward offsets at the requested radius. Contact must be within both edges. The arc splits the edges at those contacts and the existing piece, seam and notch handling takes over.

**Conventions:**

- Geometry in mm, formula numbers in the pattern unit.
- x right and y down, as on screen and in Valentina and Seamly2D. Angles in degrees, 0° right, positive anticlockwise on screen, so 90° points up. PDF and DXF, which are y up, flip on export.
- Points read `.x`, `.y`; every edge `.length`, `.angle1` (start handle) and `.angle2` (end handle, pointing back); straight edges also `.angle`.
- Curve handles are formulas (`length1 = @neck/6`). A curve path shares one tangent per node, keeping joins smooth. Shift+click with the Curve tool carries the curve on through the next point (`TPattern.ExtendCurve`), keeping the edge's ID.

**Crossings.** `extend` runs an edge on past its ends, so construction lines are not needed just to find a crossing. `pick` stores which crossing, counted along the first edge, so the result stays the same crossing when measurements change.

**Split edge** makes two parametric parts for dart rotation and slash-and-spread; the source becomes construction, and pieces and seams that used it take the parts in the same step (`TPattern.FollowSplit`).

**Repeat.** N evenly spaced points between two points or along an edge, for buttons, pleats and notch rows. `count` is a formula, so the points are virtual: only the repeat is stored, its points named `Btn[1]` … `Btn[6]`. A point gets an ID the first time something uses it (`TPattern.UsePoint`), recorded against its index in `points[]`, so it keeps that ID when the count changes; references to indices that disappear become errors, and come back when the count rises.

## Transforms

One operation that makes parametric copies of points and edges, so rotated, mirrored or moved copies follow measurement changes: dart rotation, slash and spread, mirroring a half, moving a section aside to develop it. Rotate turns about a pivot by a formula angle; Mirror reflects in a straight edge, two points, or a point and an angle; Move shifts and can turn.

- **Copies are real objects**, with IDs and names made once (`A_r1`), recording source and transform. Their geometry is computed, so they cannot be dragged, but they can be inputs to anything. A copy transforms its source's segments exactly. Pieces are not copied: clicking inside a copied outline makes a new piece.
- **In the graph** the transform works out one `TAffine2`, and each copy depends on the transform and its own source, so a failing source blocks only its copy.
- **Behaviour.** One undo step. A source cannot be deleted while copied; deleting a transform takes its copies unless something else uses them. Tools → Transform has Rotate Copy, Mirror Copy and Move Copy; Move starts with `dx` the sources' width plus a gap (`MoveAsideText`), so the copies show beside the sources. Cut on fold is a piece property applied at output; Mirror is for geometry the draft needs.
- **Separating front and back**: draft them overlapping, Move Copy the back's outline aside, make the back-only originals construction and click inside each outline. A measurement change moves both, and the overlapped draft stays the master.

Code: `Sloper.Core.Transform` (`TTransformObject`, `TPointCopy`, `TEdgeCopy`).

## One canvas

A pattern is one drafting area, drawn in pattern order with pieces under edges and edges under points. There are no drafts or layers (an older file's `drafts` and `layer` are passed over): they added rules for little use, and front and back share points and lines that would have to belong to one layer. Isolating, hiding and stacking pieces cover what layers were wanted for.

**One garment or product per file.** Garments that share no geometry are separate files, brought together in the publish and drape apps. Pieces whose geometry depends on each other (a sleeve cap from the armhole) stay in one file. References between files are not planned: they would need a dependency graph across files and IDs unique beyond one file.

**View state is kept out of undo.** Zoom, centre, hidden roles, hidden annotations and the piece view options are saved in the pattern's `view` but left out of undo snapshots and the modified flag.

## Drafting experience

**What a point is placed from** (issue #116) shows in the Properties tab after its name, as read-only rows: an offset's base, the edge a point lies along and the end it is measured from, a between point's two points, a crossing's edges, a compass step's centre and edge, a projection's point and edge, a corner end's arc, a repeat point's repeat and a copy's source. `PointInputs` in `Sloper.Editor.PropertyRows` lists them for both editors.

**Changing a point's type** (issue #81, `TPattern.ConvertPoint` in `Sloper.Core.TypeChange`). Snapping still decides the type when a point is made; changing it afterwards is a correction, offered only where the design allows it. A point can become a free point, an offset (across and down from a point), a point along an edge, between two points, a crossing of two edges, a compass step onto an edge, two compass steps or a projection onto an edge, reading the inputs `POINT_CONVERSION_INPUTS` gives. It keeps its ID, name, marker and users, so nothing that reads it changes. Its numbers are plain, worked out from where it is now, so it stays put: lengths from the nearer end or the first point, as the Point tool measures, radii from the centres, a projection square to the edge when the point is the foot of the perpendicular and otherwise at the angle it lies at. Where the new type puts it on an edge, line, circle or crossing it moves to the nearest such place (a crossing beyond an edge's end only when nearer), and is refused beyond `MAX_CONVERT_MOVE` (10 mm). Formulas it had are replaced, so the formula suggestions can turn the numbers back into formulas. Refused for a repeat's points, copies and a rounded corner's ends, which belong to what made them; for inputs that read the point; and for the type and inputs it already has. In the apps the point is the first selected and the inputs the other selected points and edges, in selection order: Tools → Points → Change To on the desktop, the *Change point to…* box on the web toolbar (`editor_convert_point`, the types from `editor_tables`), both through `ConvertPointSelection` in `Sloper.Editor.SelectionEdits`, one undo step whose status message says how far the point moved, that its formulas became numbers, and, for a free point while a size table is used, that it stays put in every size. The Automation API's `convert_point` names the type as the pattern file does and takes the inputs as `from`.

The canvas feels like Inkscape, but every point records how it was placed relative to others. Inkscape itself was rejected as the drawing tool: it stores absolute coordinates.

**Snap-inferred operations.** The snap target decides the operation recorded: a point level with A at 250 mm becomes an offset from A with `250` ready to change to `@waist/4`; a crossing becomes an intersection; empty space a free point. This is construction-based, not constraint-based like FreeCAD's Sketcher, so no solver is needed. Snapping (`Sloper.Editor.Snap`) looks within 8 pixels, in order: a point, a crossing, a place on an edge, a spot level with or square to a point, else a free point. The status bar says what a click will make.

**Canvas** (`Sloper.UI.Canvas`, with the LCL-free `Sloper.Editor.View`, `Sloper.Editor.Scene`, `Sloper.UI.CanvasInput`, `Sloper.Core.Drag`):

- **Edits to the selection** (`Sloper.Editor.SelectionEdits`): each checks the selection fits, makes one undo step and returns what to select and show, so the rules are tested without the LCL.
- **Drawing** (`Sloper.UI.PatternPainter`) draws what it is handed and decides nothing. Outlines solid, construction thin, grey and dashed; errors red, blocked orange, failing objects faded at their last good result.
- **Selection.** Points win over edges, both over pieces; Shift adds; a box selects what is wholly inside.
- **Dragging** changes only plain-number fields, rounded to the unit's step: a point with one field a formula moves along its other field only (`PartialDragField`), drawing that field's guide (a free point whose x is a formula moves up and down), and one with no plain field refuses, saying why. Handles with a formula are drawn hollow and refuse. Arrow keys nudge 1 mm (10 with Shift).
- **Deleting** is refused while something else uses an object. Only Delete or Backspace deletes; Shift+Delete means Cut elsewhere, so it does nothing here.
- **One gesture at a time** (`Sloper.UI.CanvasInput`): a drag holds an open document change until its button is released, so other buttons and editing keys are ignored meanwhile; Escape cancels.
- **Changing an edge's type** (`ConvertToLine`, `ConvertToCurve`) keeps its ID, role and users. Refused where straightness matters (a fold, a mirror axis, a line whose `.angle` a formula reads).
- **Merging points** (`TPattern.MergePoints`) keeps one definition and moves every user to it; **breaking a point** (`TPattern.BreakPoint`) gives each edge its own point at an offset of 0, 0.
- **Labels** are hidden by default and appear when they help (View → Labels: Contextual, All or None; N shows all). They print only when turned on. Notes stay where they are put, and a label moves out of their way: `Sloper.Core.LabelPlacement` tries each label round its point, along its line or above and below its piece's middle, and keeps the first place clear of notes, points and the labels placed before it (pieces' first, then points', then lines'), or the least covered. The canvas and the draft SVG place them alike; the SVG also keeps them inside the drawing.
- **Zoom tool** (Z), as Inkscape's. The publish preview has the same as View → Zoom Area.
- **Tools** (`Sloper.UI.CanvasTools`): each drawing tool is a `TCanvasToolHandler` with its own handlers and state, reaching the canvas only through `TCanvasToolHost`. A new tool is a class and a row in `CanvasToolInfo`, the table of keys, icons and captions the canvas and Tools menu share.
- **Locked objects.** Edit → Lock saves `locked` on the object: drawn greyed, still selectable, copyable and usable as an input, formulas still run, but it cannot be moved, edited or deleted. Besides the checks in drags and `TPattern`, the document records each locked object's definition at `BeginChange` and undoes any change that alters one (`ChangeRefused`), so no path gets round it. Unit conversion turns the check off for its own change.
- **Copies** are drawn as small neutral diamonds; hovering one draws a faint dashed line to its source (`CopyLinks`), and Go to Source selects it.

**Toolbars and icons.** Every command is a `TAction` shared by menu and toolbar (through `TCommandSet` in the measurements and publish apps). Keys come from `Sloper.Core.Shortcuts`, which also writes the shortcuts page. Qt names the `=`/`+` key `=`, so Zoom In is set as the keypad's Plus and `SetActionShortCut` adds Ctrl+= as a secondary key. Tooltips appear above the pointer (`Sloper.UI.HintPlacement`). Icons are Tabler SVGs in `data/icons`, drawn by `Sloper.UI.Icons` in the theme's text colour; which icon each command shows is `APP_ICON_NAMES` in `Sloper.Core.IconSet`, whose `IconCommands` also makes the Icons page. Qt draws dividers too faint on dark themes, so the app draws its own.

**Properties panel** (`Sloper.UI.Properties`): one row per field, name left and value right, so the selection fits a narrow panel. Enter or leaving commits one undo step; Escape reverts; a refused formula keeps its text, shows the reason under the field and puts the cursor at the problem. The rows come from **section objects** (common, edge, marker, repeat, piece, seam, note) made per selection, so no control can outlive its rows; changes that add or remove rows run after the handler returns. Text worked out for the panel is in the LCL-free `Sloper.Editor.PropertyText`.

**Formula completion** (`Sloper.UI.FormulaCompleter`, `Sloper.Editor.Completion`): `@` lists measurements, `#` variables, a dot an object's properties, a bare word everything.

**Formula suggestions** (`Sloper.UI.FormulaSuggest`, `Sloper.Editor.Suggestion`). A wand beside a field opens a list of formulas whose value is close to the field's (`@waist/4` for a `dx` of 175), shown as a row under the field rather than a popup, so the point can be dragged while it updates.

- **Candidates:** a brute-force search over a few shapes (`TSuggestionSource`): `@m/k`, `@m/k ± c` (round amounts or a variable), `(@a - @b)/k`, `#v/k`, `Edge.length/k`, other points' coordinates and midpoints; multiples of 45° and edge angles for angles; fractions for ratios. Objects that read the field's object are left out, so no candidate moves while the point is dragged.
- **Ranking:** closeness, then a cost favouring the simple and likely (a measurement running the field's way, one the pattern already uses), then length. Within 5 mm, 1° or 0.01; at most 6 rows show.
- **Drag locked to the field:** while the list is open, dragging or nudging the point changes only that field, constrained to its direction (`CanDragField`, `DragPointField`, `NudgeField`), even when it holds a formula, which the drag replaces with a number in the same step.
- **Grade check:** with a size table each row shows its values at the smallest and largest sizes, and hovering ghosts the pieces at those sizes, so a formula that matches by coincidence stands out. It works on copies of the pattern, one per size, never the pattern itself.
- Hovering a row ghosts the point where the formula would put it; choosing one writes it as one undo step. Alt+Down opens the list.
- **Names on the canvas:** with Contextual labels, the canvas also labels the objects the rows in view read (`SuggestionObjectKeys`), so `C.x` or `Hem.length/2` can be found on it; scrolling the list changes them. None still shows no labels, as the user chose.

**Spacing** (`Sloper.UI.Spacing`). Every app lays controls out on one gap, 8 pixels at 96 dpi scaled to the screen, between neighbours and from a container's edge, set through `ChildSizing` (`SpaceChildren`, `SpaceBetween`, `SpaceButtons`). Dialogs fit their contents when shown, then keep that size.

**Side panel tabs** (`Sloper.UI.SideTabs`). A column of tab icons down the panel's left, as in Blender, with one tab open beside it under its title. Clicking the open tab's icon folds the panel to the column; any icon, or anything that opens a tab, opens it again. Layout is in the LCL-free `Sloper.UI.SideTabsLayout`. The publish and drape apps use the same control. Each app keeps its open tab in the settings by key (`sideTab`, `publishTab`, `drapeTab`), not position, so reordering tabs never opens the wrong one. Every app's panel ends with a **Problems** tab (`Sloper.UI.ProblemsPanel`, which knows no document), its icon at the foot showing the count.

**Editable lists** (`Sloper.UI.ListPanel`): a search box over a list, with the selection held by key. Values are edited in the grid where they fit a cell (F2, Enter or typing; Escape reverts); a refused value keeps its text with the cell red. Commits go by the row's key after the cell closes, in the LCL-free `Sloper.Editor.PanelEdits`. Materials is the exception, edited in a dialog, since colour and fill do not fit a cell.

- **Variables** are edited in the grid, one undo step per cell.
- **Importing variables** (#79, `Sloper.Core.VariableImport`): the Variables tab's Import… and File → Import Variables… add the variables of another pattern file, so values set up once (eases, standard amounts) and a tutorial's variables need not be typed again. One undo step; the other file is read into a scratch pattern and only its variables are taken, with new IDs. A name this pattern has is kept, never overwritten: the user deletes it and imports again for the file's one. Kept names whose formula differs are a warning, the same ones only noted; an imported formula reading a kept variable reads this pattern's one. Different units are refused, as for paste, since a formula's plain numbers are in its pattern's unit. The API's `import_variables` takes a path or the file's text; the design window allows a path, since reading a file loses no work.
- **Measurements** edits are held until Save (see [Measurements app](measurements-app.md)).
- **Test size** scales every measurement the pattern reads by 1% a step, up to 20% either way (`TPattern.MeasurementScale`): session state, never saved, and the set cannot be edited until it is back at 0%.

**Pieces.** The Piece tool makes a piece with one click inside a closed outline; a region with a piece selects it. A notch click adds a notch to every piece on that edge, so both sides of a seam match.

**Automatic piece detection** (`Sloper.Core.PieceDetect`): build a planar graph from outline edges split where they cross, walk faces taking the next edge clockwise, pick the face holding the click and set each edge's reversed flag so the path runs clockwise, so nothing is drawn in a particular direction. A piece refers to whole edges, so a face bounded by part of one is refused, naming the edge to split. Where panels overlap, a second pass treats edges as whole and finds the smallest simple closed path round the click.

**Piece details** (`Sloper.Core.Piece`, `Sloper.Core.SeamAllowance`):

- **Grainline**: an angle or two points; new pieces start at 90°.
- **Notches** on a point on the seam line or at a position along an edge, drawn as a 6 mm mark square to the edge.
- **Cut and fold**: a cut count, a mirrored flag and `foldEdge`, a straight edge with no allowance and a bracket. The draft stays half a piece; output opens it.
- **Seam allowance**: the piece's width and an edge's own (`edge2.allowance`). Clipper2 offsets with one width per path, so `OffsetOutline` builds the raw offset with a width per segment (mitred, bevelled past four times the allowance) and Clipper2's union removes the loops.
- **Mirrored ends**: a path entry's `allowanceEnd` is `mirror` for an edge whose allowance ends mirror its neighbours', as a hem's do so they lie along the side seams turned up (`TAllowanceEnd`, `SetAllowanceEnd`); plain is left out of the file. At a convex corner between a mirrored segment and one that is not, `OffsetOutline` runs the neighbour's cutting line on to the mirrored segment's line and back as its reflection to that segment's cutting line, in place of the mitre; square to it the two are the same. Only the segments at the corner are used, so a curved side is mirrored by its tangent there. Splitting an edge keeps the setting on both parts, and joining keeps it when either had it.
- **Dart caps**: a piece lists its capped darts (`darts[]`: the two leg edges, neighbours in its path meeting at the apex, and the leg whose side it is pressed towards; `TPieceDart`, `SetDartCap`). A capped dart's legs have no allowance; instead `OffsetOutline` unions a fan from the apex that covers the dart's opening and its cap. The cap is worked out as by hand: the side not pressed to turns about the apex until its leg lies on the other (the dart closed), the outline round the dart in that state is offset with the same rules as any outline, and its cutting line between the folded centre line and the leg is the cap, mirrored in that leg for the half beside it and turned back for the other half; the cutting line past the leg, turned back, covers the corner on the other side. The properties offer a cap for each seam joining two neighbouring edges of the piece (the darts the Garment tab closes).
- A piece is a node whose inputs are its edges; a gap over 0.01 mm makes it invalid.

**Overlapping pieces.** View-state options on the selected pieces, kept out of undo:

- **Hide Piece** takes it off the canvas with everything only hidden pieces use (`DependencyKeys`); a line shared with a shown piece stays. Hidden pieces still print and export: only Export Draft follows the screen.
- **Isolate Piece** draws everything else faint and unclickable.
- **Bring to Front** and **Send to Back** change only the drawing order; a click still picks the smallest piece.

The core works these out (`TPattern.IsHidden`, `IsDimmed`, `IsActive`, `PiecesInDrawOrder`); the canvas, snapping, painter and Garment tab only ask.

**Align and distribute** (`Sloper.Core.Arrange`) is in the Automation API only (`arrange`): each action rewrites the points' definitions (`{A}.x`, Between points, Along edge points) so the arrangement holds when measurements change. In the app the same is written as formulas or with Repeat Points, which say what they mean.

## Copy and paste

Edit → Copy, Cut and Paste copy definitions, not positions, so a pasted object stays parametric. The main use is a second line on the same points: a pasted edge joins the same points, ready to become a stitch or fold line.

- **In the same pattern** only the selected objects are added; references outside the selection stay on the originals. **In another pattern** the selection brings the whole chain it depends on, so a collar can be taken from one pattern to another. The pattern's `identity`, a random value made with it, tells the two apart.
- Variables come with formulas that use them; in another pattern one with the same name and formula is reused, a different one copied (`ease2`). Measurements match by key.
- Pasted objects take fresh IDs and free names, as one undo step. Only points, repeats and edges are copied; what the chain needs but cannot copy is listed in `needs` and refused in another pattern. Pasting between patterns of different units is refused.
- When a text field has focus, Cut, Copy and Paste act on its text.

The fragment (`opensloperFragment`) holds `identity`, `units`, `selection`, `variables`, `objects` and `needs`, with the names as plain text beside it for formula fields. `Sloper.Core.Fragment` builds and pastes without the LCL; `copy_objects` and `paste_objects` do the same in the API.

## Links and problems

Direction and dependency marks appear only on hover or selection, never permanently.

| Link | Shown when | Form |
| --- | --- | --- |
| Piece direction | Hovering or selecting a piece | Chevrons at each edge's middle |
| Copy source | Hovering or selecting a copy or its transform | Faint dashed line to the highlighted source |
| Inputs | Hovering or selecting a point or edge | Faint blue arrow to each point and edge it reads |
| Dependents | As inputs, with View → Dependents on | Faint purple arrow to each point and edge that reads it |

Dependency arrows (`DependencyLinks`) use the evaluator's graph, so formula references count as inputs do. Only points and edges are linked; an edge's own ends and copies are left out, and a selection over 10 objects gets none.

**Problems** (`Sloper.Core.PatternCheck`) are listed in plain words and counted in the status bar: failing objects, gaps where a piece no longer closes, seams out of tolerance, pieces too big for their material, markings outside their piece, and outline edges in no piece. Each carries the key of its object (`PatternProblemList`). The canvas draws a faint red halo under each object with a problem (View → Problems, `showProblems`). The same list is the Problems tab, the Objects tab's filter, `check` in the CLI and the API.

**Objects tab.** Every point, edge, piece and note with its name, operation, formulas, value and state, with search (names, operations, formulas and note text) and a filter. Edit → Select Next and Previous (Ctrl+Tab, Control on macOS too) step through it, keeping the cursor in the same field of the next object, so a run of formulas can be checked without the mouse (`StepKey`).

## Markings

Internal markings (placement, stitch and fold lines, holes, buttons) are drawn like any line or point and given a role or marker, and the app attaches them to the right piece itself. Seamly2D and Valentina make the user add each internal path to a piece; markings must belong to a piece to move with it in layouts, and overlapping pieces make that ambiguous, so OpenSloper resolves it automatically.

### Edge roles

| Role | What | On paper |
| --- | --- | --- |
| Construction | Thin dashed guide | Never |
| Outline | Piece boundary | The cutting line |
| Placement | Pockets, trims, button bands | Thin, solid |
| Stitch | Topstitching or an internal seam | 1 mm dashes |
| Fold | Fold or pleat line | Dash-dot |
| Cut | Slit or internal cut | Solid |
| Skive | How far a leather edge is thinned | 4 mm dashes |
| Edge finish | How far edge paint, burnishing or binding runs | Dotted |

Roles are a fixed list, like KiCad's technical layers, so output settings can rely on them. On screen each marking role has its own colour, clear of red and orange, which mean problems; on paper they are black (`ROLE_DASHES`). For machines fold is a score line and cut is cut; DXF-AAMA writes markings on layer 8. Where lines coincide the higher role draws on top (`ROLE_PRIORITIES`). Tools → Draw As, shown on the command bar, chooses the role of lines drawn next.

Preferences → Design → Line Styles sets the screen colour, line pattern and width for each role. The Design canvas and Lines tab use these settings.

### Point markers

| Marker | Use | Drawn as | Starting size |
| --- | --- | --- | --- |
| Plain | Ordinary point; not printed | | |
| Hole | Dart points, pocket corners, rivets, snaps, eyelets | A circle, cut as a hole | 4 mm |
| Button | Button and buttonhole positions | A circle with a cross | 15 mm |
| Match dot | Matching points between pieces | A small dot | 3 mm |
| Buttonhole | Buttonholes | A slot its size long with a bar tack across each end; cut as a slit by machines; hidden under its button in the Garment tab | 18 mm |

The marker and its size (`markerSize`, a formula) belong to the point, not its pieces. A buttonhole also has `markerAngle`, the way its slot runs, and `markerOffset`, how far along that its middle is from the point, so a horizontal hole can start just past the centre front; both are formulas, start at 0 (across, centred) and exist only while the marker is a buttonhole. Buttonholes are a marker rather than an edge role so that a repeat carries them, and the number of buttons stays a formula. A repeat's marker applies to all its points; a copy keeps its source's. A hole on a fold line makes the piece invalid.

### Automatic piece assignment

A line with a marking role or a point with a marker joins every piece it lies inside (a line when more than half of nine sampled points are, `LiesInside`). Inside several overlapping pieces it joins them all and the user takes it off the extra ones; inside none it is reported ("does not print"). The assignment is stored in the piece's `markings[]`, not recalculated, so markings never jump between pieces silently; one a measurement change moves outside is reported. Position is known only once computed, so `TPattern` queues new markings and `Evaluate` assigns them. Tools → Markings changes it by hand.

### Several lines in the same place

Any number of edges can join the same two points, each with its own role (`Line_A_B2`). Coinciding edges are drawn 3 px apart on screen only. A click picks points first, then the nearest edge (highest role on top), then the smallest piece; clicking again or Alt-click cycles through what is there, and a right-click lists it (`ObjectsAt`, `CoincidentEdges`, `NextKey`).

**Offset edge.** Topstitching runs a fixed distance from an edge, so an offset edge makes it from one edge or a run joined end to end, following its sources. Outer corners mitre as allowance does, inner corners trim. Inside or outside a piece is worked out once and stored as left or right, so the offset reads only its edges, never the piece (which would be circular). Tools → Offset → Inside Piece makes a stitch line that joins the piece. Where an inner corner leaves no room for a part, so the mitre falls past its end, the parts either side are joined where they cross, carried on straight if need be (`CrossJoin`); a short part swallowed whole between its neighbours, as the step out to a button extension under a facing's width, is left out (`JoinAll`), and only a run whose first part is swallowed collapses. Either end can be **limited** by an edge (`startLimit`, `endLimit`): the offset is cut back to where it crosses that edge, or carried on straight along its end's direction to it, the crossing nearest that end, and its end is moved exactly onto the crossing so a point there can split the limit. A facing's inner edge meets the shoulder and centre front this way whatever the width or the angle at the corner; a limit it cannot reach makes it invalid.

A fold on the piece's own edge is not a line but the piece's `foldEdge`.

### Role visibility

The Lines tab (`Sloper.UI.RolesPanel`) shows or hides Construction and each marking role, with Solo, Show All, Hide All and presets. It changes the view only: hidden lines are still stored, evaluated, printed and checked, and the status bar says how many kinds are hidden. Saved as `hiddenRoles` in `view`; presets are the user's, in `settings.json`. Which markings reach paper is the publish app's choice.

## Seams

A seam records that edges are sewn together. It is its own object, since nearly every outline edge is sewn and a role could not name the partner. The app cannot work seams out (a sleeve cap is meant to be longer than its armhole, and a shared edge need not be sewn), so the user makes them and the app suggests them.

- **The object.** `sideA[]` and `sideB[]` each list `piece` and `edge` in order. A side can span pieces and have gaps; both sides may use one piece (dart legs) or one edge (a centre back on a mirrored piece); several seams may use one edge.
- **Whole edges only.** Splitting an edge moves its pieces and seams onto the parts in the same step (`TPattern.FollowSplit`), so lengths are unchanged.
- **Direction.** Each edge runs the way its piece's clockwise path does, so sewn edges normally run opposite ways and side B pairs from its far end; `reversed` flips it, mostly for mirrored pieces.
- **Length check.** `ease` (what side B has over side A) and `tolerance` (1 mm) are formulas, so gathers follow the pattern. A mismatch is a problem, not a state. Unsewn edges are not reported, since a hem cannot be told from a forgotten seam.

A seam's inputs are its pieces. Seams have no place on the canvas, so they are selected from the Objects tab. The Seam tool (E) clicks edges onto side A, Tab to side B, Enter to make it; a selected seam shows chevrons and Flip. **Suggest Seams** lists likely pairs, none ticked: shared edges first, then edges within 1 mm of each other's length.

## Materials

Pieces are coloured by the material they are cut from, so colour carries meaning. They are called materials, not fabrics, because leather, foam and stiffener go in the same list.

- **The list.** Each material has an ID, a name (its own namespace), a colour, a fill (tint or hatching), an optional default allowance, size and fabric. Changes are undo steps. The last material, or one in use, cannot be deleted.
- **Size.** A width alone is a roll, width and length a sheet, neither no check; `allowTurns` is for material with no grain. Each valid piece is measured as it lies on the material, turned so its grainline runs along the length and opened out on a fold; one wider than a roll or past a sheet is a problem (`AddMaterialFitProblems`, `GrainShape`). Whether all pieces fit together is the publish app's Material needed.
- **Fabric** (cotton, silk, jersey, wool, denim, canvas, leather; `TFabric`) says how it drapes in Blender; none drapes as cotton. Named fabrics rather than numbers, since a pattern maker knows the fabric, not Blender's units.
- **Assignment.** Each piece is on a material and takes its fill from it, with an optional per-piece override, and takes the material's allowance when put on it (not following later changes). A piece with no material is unfilled and reported.
- **Starting out.** A new pattern has one material, Main, which has no ID and is not written until the list first changes, so simple files stay simple.
- **Display.** Fills are semi-transparent and under every line; the palette stays distinguishable for colour-blind users, and the name is in the piece label, so colour is never the only cue. Hatching angles go by place in the list, so hatched materials differ in black and white. Printing fills is off by default.
- **Cut list** grouped by material ("Main: Front ×1 on fold, Back ×2 · Lining: …"), the `{cutlist}` field.

Code: `Sloper.Core.Materials`, `Sloper.Core.PatternMaterials`, with `TPattern` answering `MaterialOf`, `PieceLook`, `PieceCaption` and `CutList`, so the canvas and every export ask the same place. The Materials tab is read-only (`Sloper.UI.MaterialPanel`); editing is in `Sloper.UI.MaterialDialog`, each field one undo step applied at once. The list's rows and the fill and fabric captions are in the LCL-free `Sloper.Editor.MaterialList` and the edits in `Sloper.Editor.PanelEdits`, so the web editor shares them through `editor_materials`, `editor_material`, `editor_material_set`, `editor_material_add` and `editor_material_delete`.

## Annotations

Notes, callouts and information blocks print with the pattern, a gap found in practice with Seamly2D.

| Kind | Lives in | Anchored to | Typical use |
| --- | --- | --- | --- |
| Note | Pattern | A point, edge position or piece, plus an offset; or free | "Stay-stitch neckline" |
| Callout | Pattern | Text anywhere, leader tip on a point, edge position or piece | Pointing at a notch or dart |
| Stamp | Pattern | As a note | A logo, a folding or assembly diagram |
| Piece label | Pattern | Its piece | Name, cut count, on fold |
| Information block | Layout | A page corner | Pattern, measurements, size, date |
| Sheet note | Layout | A place on the printed layout | Instructions, notions |

**Anchored, so notes stay parametric.** A note stores its anchor's ID and an offset (`dx`, `dy`, formulas), so it moves with the geometry; a free note has `x`, `y`. Its anchor is its input: it is blocked while the anchor fails, and the anchor cannot be deleted while used. Make Free turns a note free where it is. `print` false keeps a drafting note on screen only. View → Annotations shows or hides them all.

**Fields.** Text can hold document fields (`{pattern.name}`, `{measurements.name}`, `{size}`, `{date}`, `{page}`, `{pages}`, `{cutlist}`, `{materials}`, `{materialneeded}`), filled by `Sloper.Core.TextFields`, and draft values such as `{=Line_A_B.length}`, each a formula field of the note (stored inline in ID form). A note that prints with exactly one piece also fills `{piece.name}`, `{piece.cut}` and `{piece.material}`, so a note can be a custom piece label; in a layout each placed copy fills its own.

**Callouts** are notes with a `leader` (`arrow`, `dot`, `line`): one object and one file type. Dragging the tip re-anchors it (`SetNoteAnchor`). `align` and a white `box` work alike for pattern and sheet notes.

**Stamps** are notes with a `drawing`: an SVG drawing from another app, drawn in place of the text, which only names it in lists (the file's name to start with). One object and one file type, as callouts are, so anchoring, dragging, Make Free, the leader, the box, printing with a piece and the layout come with it.

- **Reading** (`Sloper.Core.SvgImport`): paths and the basic shapes (rect, circle, ellipse, line, polyline, polygon), through groups, nested `svg` and every transform, with fill, stroke, stroke width, fill rule and `currentColor` from attributes and the `style` attribute, inherited down groups. Arcs and quadratics become cubics. Text (`text`, `tspan`, `textPath`, `flowRoot`) is refused with a message asking for it to be converted to paths, which keeps fonts out of patterns; bitmaps (`image`, `foreignObject`) and clones (`use`) are refused too. Elements of other namespaces (Inkscape's, Sodipodi's), `defs` and the like are skipped, as is what is hidden. Gradients are drawn black; style sheets, clipping, masks and opacity are left out; each with a warning.
- **True size** from the root's `width`, `height` and `viewBox` (fitted whole, keeping its shape). Without a real unit (mm, cm, in, pt, pc) the size is in pixels, taken at 96 to the inch, with a warning. `scale` (0.01 to 100, a plain value) makes it bigger or smaller.
- **Kept in the pattern** (`Sloper.Core.Stamp`) as path data in mm from the drawing's top left, only `M`, `L`, `C` and `Z`, absolute, to a thousandth of a mm, with each path's fill and stroke as `#rrggbb` and its stroke width, so the pattern does not depend on the file. At most 50,000 segments. The drawing is a value nothing changes; another drawing replaces it.
- **Drawn** in its own colours everywhere: the canvas and the publish preview (`DrawStampOn`, BGRABitmap), the draft and layout SVG (`StampElements`), the layout PDF (paths with `f`, `f*` or `B`; all in ink on a projector), and the web canvas (`Path2D` from the scene's `stamp` paths). Faded as text would be when dimmed or screen-only. In a layout it stays upright with its piece, as text does. Not written to DXF, as notes are not.
- **Adding** (`AddStampStep`): File → Import SVG Stamp... centres it on the one point, edge (its middle) or piece selected, or free in the middle of the view; in the API, `add_note` and `set_text` take `svg` and `scale`, and reply with the warnings. Its rows are the name text, Scale, Print, Box and what it hangs from.

**Typing.** Text is typed in the properties: the Text tool and a double-click on a note put the cursor there, and the canvas previews the note as it is typed (`PreviewNoteText`), with no undo step until the field is left. A text box over the canvas was rejected: it would have to follow zoom and scroll and switch between formulas and values.

**Fonts.** A family (`font`), `bold` and `italic` on pattern and sheet notes alike (`TTextStyle`); names are checked so they cannot break a font list, a file or an SVG attribute.

- **Finding a font** (`Sloper.Output.Fonts`): the bundled fonts first, then the system's (`TAppPaths.SystemFontDirs`), read with FCL's TrueType parser in a fixed order so the same machine always picks the same file; answers cached behind a lock.
- **Measuring.** A named font's real widths are used everywhere (canvas, SVG, PDF, layout checks). The default font is estimated from Helvetica's average width, so layouts do not move.
- **PDF.** A named font, or the bundled Noto Sans for text Helvetica cannot print, is embedded as a CIDFontType2 with a ToUnicode map, subset by our own `Sloper.Output.FontSubset` (glyph numbers kept, tag from a checksum, so the same text gives the same bytes). A missing style is drawn (stroked bold, slanted italic). A font that is missing, CFF, or forbids embedding prints in the default font with a warning.
- **PNG** draws with the bundled fonts only.

## Accessories

The same parametric core drafts bags, pouches, wallets, hats and belts in fabric and leather. A bag is driven by product dimensions (`#width`) or a size table of them; nothing in a measurement file assumes a body.

- **Circles and arcs**, for round bases, crowns and brims that need exact lengths. Stored as cubic segments of at most 45° like every edge, with `.length` and `.radius` from the exact formulas. Their ends are not points: an along-edge point joins a line to one.
- **Rectangle tool** (R): three offset points and four lines from `width` and `height` formulas, in one step.
- **Rounded corners** replace the corner between two straight edges with an arc of a formula radius (`cornerArc`), trimming both at tangent points (`cornerPoint`); the original corner stays as construction, and pieces, notches and seams follow onto the arc (`TPattern.FollowCorner`).
- **Stitch holes** along an edge take a spacing formula and size, spread evenly between the ends; `.holes` counts them.
- **Leather** is usually cut with no allowance: an edge's allowance can be 0, a material can carry a default, and an output profile can cut on the seam line.

Fashion drawing is left to Inkscape and Krita; hardware sizes are variables.

## Features

The **Features** tab (`Sloper.UI.FeaturesPanel`) applies a sewing detail (zips, darts, hems, facings and buttons now; pockets later) in one step. **A feature is not an object**: Apply adds ordinary objects through the pattern's own methods, in one undo step, and nothing is saved as a feature, so the file format, evaluator and API stay as they are and the objects are the user's to edit. Changing a feature means undoing and applying it again; a feature kept as one editable object may follow once it is clear which settings people change. The features are in the LCL-free `Sloper.Core.Features`. The tab's forms are in `Sloper.Editor.FeatureForms`: each feature's fields (always the same ones in the same order, so the panel builds its controls once), their captions in the pattern's unit, choices (an edge's ends, the materials), starting values and whether they apply now, worked out from the selection and the values so far, as text (a choice's index, `1` or `0` for a box); the values that follow a change (another style starts again at its own widths, a hem's topstitching follows its depth until it is typed in itself); and Apply, one undo step with the message the status bar shows. The desktop panel builds its controls from them, and the web editor reads them through `editor_features` and `editor_feature_apply`.

**Dart** (`InsertDart`, `TDartSpec`, `DefaultDart`) in one selected outline edge of one piece, optionally to a selected point:

- `DartMid` along the edge at the position (halfway when none is given), from the start or the end, and a `DartLeg` either side at ± width / 2 along the edge (`AddAlongEdgePoint`, so they follow a curve).
- `DartApex` at the depth from `DartMid`, square to the chord between the legs and into the piece; a picked point is used as it is, so the dart follows it.
- The legs as outline lines; the edge is split at both legs (`FollowSplit`), the part between becomes construction, and `ReplaceInPath` puts the legs in its place in the piece's path. Notches on that part go, and seams that sewed it leave it out, as a dart's legs are not sewn to what the edge was.
- A seam `Dart` between the legs (the Garment tab closes it), a notch at each leg, a Hole marker on a point back along the centre line from the apex, the centre line as a Fold marking, and the dart cap pressed towards the chosen end.
- Refused: an edge in no piece or in more than one, a fold, a width of 0 or one running past an end, a depth of 0 or less, an apex outside the piece, and legs that would cross another edge of it.

**Hem** (`InsertHem`, `THemSpec`, `DefaultHem`) along one or more selected edges, on one or more pieces, single, double, narrow or blind:

- Each piece's selected edges are one run (`PieceRun`); a piece whose edges do not join end to end is refused, as are an edge in no piece and a piece's fold.
- Each edge gets its own allowance, the depth or the depth plus the turn-under, and mirrored ends (`SetAllowanceEnd`).
- The depth is `#hem_depth`, a variable the first hem adds, so hems on several pieces share it; a narrow hem starts with a number of its own. The topstitching starts 3 mm short of the depth (`HemStitchDistance`), an offset run inside each piece (`AddOffsetRun`), none for blind.
- A notch at each end of the run, in the neighbouring edge at its end (`AddEdgeNotch`), unless turned off or the neighbour is the fold.
- A hem at least as deep as the piece is tall above the line between its ends is made but reported (`THemMade.Problems`), since a deep hem can be a facing.
- A double hem's inner fold is not marked: it lies in the allowance, outside the piece, where markings cannot go, and the allowance already includes the turn-under.

**Facing** (`InsertFacing`, `TFacingSpec`, `DefaultFacing`) along one or more selected edges, on one or more pieces, such as a neckline, an armhole or a front opening:

- Each piece's selected edges are one run (`PieceRun`); edges in no piece, edges that do not join end to end, a run with the piece's fold in it, one all round the piece (a lining) and one with the same edge at both ends are refused.
- The inner edge is an outline offset run inside the piece at the width, limited by the edges before and after the run in the path: going on round the path from each end, the first edge its ends, carried on straight, reach (`OffsetLimitCrossing`). An edge passed on the way must lie within the width of the run at both ends (`WithinFacing`), as the step back in from a button extension does; the facing takes it whole. A shoulder further from the neck than the width stops the walk, so a facing too wide for the piece is still refused. An Along edge point at each end splits those edges (`FollowSplit`), so the piece keeps its shape and its seams take both parts. An inner edge that cannot reach a neighbour, or reaches it at its far end, is refused as wider than the piece there.
- The facing piece, `Facing_` and the piece's name, runs along the run, the part of the edge after it, the inner edge back and the part of the edge before it. It takes the piece's allowance (and its edges' own), grain (an angle, or the angle between grain points as a formula), material, cut count and mirroring, and is cut on the fold along the fold's part when a neighbour is the piece's fold.
- A `FacingSeam` joins the run on the piece to the run on the facing, both along their paths (`Reversed`), and where a seam joins neighbouring parts of two faced pieces (the shoulder), a seam joins the facings' parts too. The piece's notches on the facing's edges are copied.
- The width is `#facing_width`, a variable the first facing adds at 60 mm, 6 cm or 2.5 in, so the front's and back's match.
- **Moved aside**, the facing's edges and notch points are copied by a Move Copy the piece's cutting line's width and a gap to the right (`MoveAsideWidthText`), the facing is made of the copies, and the inner edge on the piece becomes construction, showing where the facing goes.
- An **interfacing**, `Interfacing_` and the piece's name, has the facing's path and is cut from the material named, which is added if the pattern has none of that name.
- The run is not a detected face: the facing is a piece path given outright, so an outline edge inside the garment does not change it.

**Buttons** (`InsertButtons`, `TButtonsSpec`, `DefaultButtons`) along an opening's edge, on one piece cut twice or on two fronts:

- `ButtonTop` and `ButtonBottom` along the edge at `first` from its start and `last` from its end; a **Buttonhole** repeat between them, ends included, with the buttonhole marker, its length the size plus the thickness; and a **Button** repeat with the button marker at the size. The count is a formula, so changing `#button_count` moves and adds both with no new apply.
- Horizontal holes run square to the line from `ButtonTop` to `ButtonBottom`, into the piece (tried before an extension widens it), their middle `length / 2 - 3 mm` along so they start 3 mm past the centre front; vertical holes run along it, centred.
- `#button_size`, `#button_thickness` and `#button_count` (15 mm, 3 mm, 5) are variables the first buttons add.
- With a **buttons edge** on another piece, the buttons go along it, measured from whichever end lies nearer the holes' first (`RunsBackwards`), as on a mirrored copy; each repeat is then taken off the other piece if they overlap. Both pieces get the extension.
- An **extension** offsets the edge outwards at its width, joins it with lines at the ends and puts the three in the edge's place in the path (`ReplaceInPath`, seams leaving it out); the edge becomes a Placement line, so the centre front still prints, with the buttons on it. One narrower than half a button is made and reported (`TButtonsMade.Problems`).
- Refused: an edge in no piece or in more than one, a fold, a count under 1, and first and last leaving no room.

**Zip** (`InsertZip`, `TZipSpec`) along one selected edge of one or more pieces, in four styles, each with its own starting widths (`DefaultZip`):

- It adds `ZipStop` at the zip's length from the chosen end, splits the edge there (`FollowSplit`), gives the opening its own allowance, notches the stop, and adds the style's stitching inside each piece (`PieceRun`, `AddOffsetRun`).
- The length is `#zip_length`, a variable the first zip adds, so both sides of a seam share it.
- **Centred** stitches round the opening, **invisible** has none, **lapped** is the opening's offset plus a line across to the stop, and **fly front** a J (an offset at the fly's width with a curve into the stop, square to the opening) plus a **FlyShield** piece cut on the fold, following `#zip_length`.
- A zip as long as its edge is refused. When the edge is sewn to one without a zip, the status bar says the other side needs one too.
- In the Automation API features are methods named `feature_` and the feature (`feature_zip`, `feature_dart`, `feature_hem`, `feature_facing`, `feature_buttons`), in a Features group; `set_dart_cap` caps a dart drawn by hand and `set_allowance_end` mirrors any edge's allowance ends.

## Garment view

The **Garment** tab shows each piece as sewn, darts closed and folds opened, shaded to look slightly rounded, to glance at while drafting. It shows proportions and shaping, not how pieces join, fit or drape, which is the [drape app](drape-app.md)'s. It is read-only and saves nothing.

**Pieces side by side, not front and back.** Each piece is shown on its own, arranged as on the canvas, so the tab needs no front or back setting per piece and works on any pattern. Joining pieces into front and back views would need that setting, seam welding and registration of the two views, and the assembled look belongs to the drape app.

**The tab.**

- Each piece keeps its drafted place, turned so its grainline is upright, as it hangs. Overlapping pieces are drawn overlapping in the canvas's order, not pushed apart. It follows the canvas's hidden, isolated and stacked pieces; the API's `render` with `garment` shows every piece.
- A material filter shows one material's pieces or all, starting on the first material.
- The drawing fits the panel; the wheel zooms, a drag pans, a double-click fits. **Follow canvas** uses the canvas's zoom and centre.
- It is rebuilt after each change while showing, and only the pieces whose fingerprint (everything their finished shape follows from) changed are rebuilt (`TGarmentBuilder`).
- Hovering names and highlights a piece on the canvas too; a click selects it there. A selected seam is marked on both sides (which lines a selection marks is `Sloper.Editor.Garment`, shared with the web editor).
- Notes under it say what was left out (a dart left open and why, a failing piece).
- **Export…** saves SVG or PNG; `render` with `garment` gives the same.

**Building a piece** (`Sloper.Core.Garment`, from the evaluated pattern):

1. **Close the darts.** A dart is a seam whose two sides are neighbouring edges of one piece, meeting at the apex. Each is closed by turning the piece about its apex (`Sloper.Core.Warp`): a point at angle α from the opening's bisector moves to 180° + (α − 180°) × 360° / (360° − θ), so each leg turns half the opening θ onto the bisector and the side opposite does not move; legs of different lengths meet halfway. A dart is left open, with a note, when a leg is curved, it opens past 90°, or its inside is inside the piece.
2. **Place.** A piece with darts keeps still the outline point furthest from every apex; a fold piece keeps its fold where it was.
3. **Open the fold**, mirroring across it.
4. **Turn upright** by the grainline.

Everything on the piece goes through the same warp, so outline, stitch lines, markings and grainline all follow the darts.

**Drawing.** The core hands one scene (`TGarmentScene`) to one renderer, `Sloper.Output.GarmentPNG`, for the tab, the PNG export and the API, and `Sloper.Output.GarmentSVG` draws it as SVG, so they match.

- Outlines are seam lines; sewn edges have a fine dashed line just inside. Allowance, notches, labels, grainlines and construction are left out; buttons, holes, stitching and fold lines (as plain lines) are drawn.
- Fill is the material's colour at full strength; a piece with no material is grey.
- **Shading:** each row of a piece follows a half cylinder between its left and right sides (`GarmentShade`, a pure function tested without the LCL), lit a little from the upper left, with side widths smoothed over nearby rows (`GarmentSpans`) so a sloping hem does not make it jump. A long narrow piece lying across (a waistband) is shaded down its columns instead. Seams get a soft shadow and highlight; each piece a drop shadow. Light direction and strength are preferences.

**Limits.** Pieces never bend beyond the dart warp, so flares, gathers and drape are not shown.
