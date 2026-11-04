# Zilla Furniture Tools

**SketchUp furniture manufacturing assistant — v0.2.0 prototype.**

This first version scans an existing cabinet model, detects conservative 90° butt joints between rectangular sheet-material parts, places **non-cutting confirmat drilling guides** and exports a UTF-8 CSV with drilling coordinates and candidate front-edge PVC banding.

## Download / installation

1. Download the source from GitHub or the release ZIP.
2. If using source, run `python tools/build_rbz.py` (Python 3, no packages required).
3. In SketchUp go to **Window → Extension Manager → Install Extension**, choose `dist/ZillaFurnitureTools-v0.2.0.rbz`.
4. Open **Extensions → Zilla Furniture Tools — drill planner** (in some versions this menu is called Plugins).


## NEW in v0.2 — Manual Smart Joint

The tool now has **two modes**:

**Auto planner**: select a cabinet assembly -> Extensions > Zilla Furniture Tools — drill planner -> Analyze / Apply guide markers / Export CSV.

**Smart Joint (manual)**: select your cabinet assembly -> Extensions > Zilla Furniture Tools — Smart Joint. Hover the pointer close to a highlighted perpendicular face-to-edge seam and click. A side dialog opens with a **fastener selector**, **fastener count (1–8)**, **offset from both seam ends** and a preview of face/edge drill centers. Press **Нанести розмітку** to add one undoable, separate group of construction markers, or export a **joint-only UTF-8 CSV**. Esc cancels a joint; click **Інший стик** to continue. Ctrl+Z undoes an applied marker operation.

The new fitting library includes provisional **confirmat 7×50** and **wooden dowel Ø6/Ø8×30 with glue**. Dowel bores are **blind and begin at the mating face**, not the outside of the carcass. Exact nominal hole diameters, depths and fit still require hardware-specific verification. Hardware catalog also lists **drawer-front adjusters**, **side-mounted** and **concealed slides**, **caster/foot plates** but these are **disabled for drilling** until the manufacturer/SKU and its hole pattern are verified.

### Support boundaries (important)

- This is an **early SketchUp beta**, still pending hands-on Windows SketchUp validation. Ruby tests and RBZ packaging can run outside SketchUp but do not verify picking/drawing callbacks.
- Works only for separate simple **rectangular, orthogonal groups/components**, with a real shared butt seam. The automated and manual modes deliberately skip complicated, angled or non-cuboid objects.
- Markers and preview are **not actual cuts** in the board, nor a DXF/CNC machining program. CSV XYZ uses active model coordinates and bounding-box-local coordinates; orientation must be checked by the shop.
- The preliminary dowel depths are illustrative and may be insufficient for the dowel length: obtain a specific manufacturer drawing before production.
- The drawer-front, slides, edging and wheel-specific tools remain planned tasks; no drilling guessed from unknown hardware.

Run tests: `ruby test/test_planner.rb && ruby test/test_hardware.rb`. Build package: `python3 tools/build_rbz.py`. Current package: `dist/ZillaFurnitureTools-v0.2.0.rbz`.

## Working with a cabinet model

1. Make each DСП panel a standalone **Group** or **Component**, with exactly six planar faces and twelve edges, 12–25 mm thick. Nested cabinet assemblies are supported.
2. Select the whole cabinet assembly or selected panel components.
3. Enter the actual screw and drill sizes and joint tolerance; set the forward facing direction (`-Y`, `+Y`, `-X`, `+X`).
4. Click **Аналізувати стики**, review joints, hole coordinates and warnings.
5. Click **Нанести розмітку** to add a removable `ZFT DRILL GUIDES — non-cutting` group to the active editing context; the original solid geometry remains intact.
6. Click **Експорт CSV** to save a semicolon-separated manufacturing sheet. This is **not** a ready-to-run CNC program.

### What automatic planning does

- Recognizes **axis-aligned rectangular panels** with optional 90-degree rotation and nested component transforms (not arbitrary angles or curved boards).
- Detects **butt joints**, when the end of one panel touches the broad face of another within the specified tolerance.
- Generates **two screw locations** at configurable offsets from the common seam ends, each with a face-through and edge-pilot drilling operation.
- Provides pilot diameter and depth, screw length, hole coordinates in the active SketchUp edit frame and coordinates relative to the minimum XYZ corner of each panel's bounding box.
- Suggests PVC edging for narrow faces in the chosen frontal direction, **requiring manual review** (does not modify OpenCutList's edge materials).
- Excludes known drawer, front, handle, slide and leg naming patterns; additionally you can explicitly classify any selected component as `drawer`, `cabinet`, or `exclude` using the plugin UI.
- Keeps all generated guides in a uniquely marked removable group, with data stored in an attribute dictionary.

### Safety and limitations

**No actual holes are cut into part solids.** This is intentional for v0.2. A marker is a visible circle and construction point, not CNC geometry. OpenCutList does not automatically pick up the marker as a real hole in the panel.

Default adjustable **confirmat 7×50 mm profile**: face clearance Ø7 mm, edge pilot Ø5 mm, pilot up to 30 mm, two screws at 50 mm from seam ends. These are assumptions for the prototype, **not a certified drilling prescription**; verify screw and bit specifications, head/countersink, panel quality, joint positions, chipboard thickness, clearance and load with the hardware supplier and fabricator.

No automatic layout for dowels/glue, drawers, telescopic slides, caster/feet or hinge patterns in this release. Those require explicit SKU-specific drilling templates, otherwise the software could damage parts. Panels overlapping the seam, missing clear butt joints or with unsupported/ambiguous geometry are skipped rather than guessed.

**Production safety:** Make a copy of the `.skp`, verify planned pilot holes in 3D, check interference/clearance and test on scrap before drilling. CSV coordinates are **world-axis bounding-box relative**, not an oriented-machine datum. Validate all workholding, coordinate systems and tool paths in CAM. PVC banding is reported as `REVIEW_EXPOSURE`, never auto-approved.

## Run tests

```bash
ruby test/test_planner.rb
python tools/build_rbz.py
```

Unit tests cover simple join, reversed join, gap, parallel boards, short seam, excluded drawer, edge suggestions, option validation. An actual SketchUp GUI integration test requires SketchUp on Windows (not available in GitHub Actions).

## Roadmap

- **v0.2:** manual approve/reject per joint, actual model surface drilling, countersinks and dowel templates.
- **v0.3:** edge visibility analysis and OpenCutList edge-material synchronization when a documented integration path is confirmed.
- **v0.4:** slides, caster feet and hinges via vendor-specific hardware templates; 2D manufacturing drawings + compatible DXF layers.
- **v0.5:** machine postprocessors with verified 3-axis orientation, pilot/countersink tooling and collision checks.

MIT license.